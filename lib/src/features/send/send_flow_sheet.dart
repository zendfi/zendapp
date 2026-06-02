import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/email_intent.dart';
import '../../models/recent_contact.dart';
import '../../services/sound_service.dart';
import 'send_shared_widgets.dart';

// Note: bank send and crypto send are now accessed via the Withdraw sheet,
// not from the send flow. The send flow is strictly zend-to-zend.

enum SendStage {
  recipient,
  pin,
  processing,
  success,
  error,
  emailIntent,
  emailIntentPin,
  emailIntentSuccess,
}

Future<void> showSendFlowSheet(
  BuildContext context, {
  required double amount,
  String? prefilledRecipient,
  String? prefilledNote,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => SendFlowSheet(
      amount: amount,
      prefilledRecipient: prefilledRecipient,
      prefilledNote: prefilledNote,
    ),
  );
}

class SendFlowSheet extends StatefulWidget {
  const SendFlowSheet({
    super.key,
    required this.amount,
    this.prefilledRecipient,
    this.prefilledNote,
  });

  final double amount;
  final String? prefilledRecipient;
  final String? prefilledNote;

  @override
  State<SendFlowSheet> createState() => _SendFlowSheetState();
}

class _SendFlowSheetState extends State<SendFlowSheet>
    with SingleTickerProviderStateMixin {
  static const Duration _stageTransition = Duration(milliseconds: 180);
  static const Duration _sheetResize = Duration(milliseconds: 220);
  SendStage _stage = SendStage.recipient;

  String? _recipientZendtag;
  String? _recipientDisplayName;

  // ── Email intent state ───────────────────────────────────────────────────
  String? _emailRecipient; // the typed email address
  CreateIntentResult? _emailIntentResult; // result after successful creation

  final _noteController = TextEditingController();

  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

  String? _errorMessage;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticOut,
    ));

    if (widget.prefilledRecipient != null) {
      _recipientZendtag = widget.prefilledRecipient;
      _recipientDisplayName = widget.prefilledRecipient;
      if (widget.prefilledNote != null) {
        _noteController.text = widget.prefilledNote!;
      }
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _sheetHeightFraction {
    switch (_stage) {
      case SendStage.recipient:
        return 1.0;   // full app height
      case SendStage.pin:
        return 0.70;
      case SendStage.processing:
        return 0.45;
      case SendStage.success:
        return 0.50;
      case SendStage.error:
        return 0.55;
      case SendStage.emailIntent:
        return 0.70;
      case SendStage.emailIntentPin:
        return 0.70;
      case SendStage.emailIntentSuccess:
        return 0.55;
    }
  }

  String get _amountFormatted {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _amountFormattedExact =>
      '\$${widget.amount.toStringAsFixed(2)}';

  void _goTo(SendStage stage) {
    setState(() => _stage = stage);
  }

  void _onRecipientConfirmed(String tag, String displayName) {
    setState(() {
      _recipientZendtag = tag;
      _recipientDisplayName = displayName;
      _stage = SendStage.pin;
    });
  }

  void _onPinKey(String value) {
    HapticFeedback.lightImpact();

    setState(() {
      _pinError = null;

      if (value == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }

      if (_pinDigits.length >= 4) return;
      _pinDigits += value;
    });

    if (_pinDigits.length == 4) {
      _submitPin();
    }
  }

  Future<void> _submitPin() async {
    final pin = _pinDigits;
    _goTo(SendStage.processing);

    try {
      final model = ZendScope.of(context);
      await model.transferService.sendTransfer(
        recipientZendtag: _recipientZendtag!,
        amountUsdc: widget.amount,
        pin: pin,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      if (!mounted) return;

      await model.recordTransfer(
        recipientZendtag: _recipientZendtag!,
        recipientDisplayName: _recipientDisplayName ?? '?',
        amount: widget.amount,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      unawaited(model.fetchBalance());
      unawaited(model.fetchHistory());

      setState(() {
        _stage = SendStage.success;
      });

      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
    } on PinDecryptionException {
      if (!mounted) return;
      _pinAttempts++;
      if (_pinAttempts >= 5) {
        setState(() {
          _errorMessage = 'Too many incorrect PIN attempts.';
          _stage = SendStage.error;
        });
      } else {
        _shakeController.forward(from: 0);
        setState(() {
          _pinDigits = '';
          _pinError = 'Incorrect PIN';
          _stage = SendStage.pin;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = SendStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = SendStage.error;
      });
    }
  }

  void _onEmailIntentSelected(String email) {
    setState(() {
      _emailRecipient = email;
      _stage = SendStage.emailIntent;
    });
  }

  Future<void> _submitEmailIntentPin(String pin) async {
    final email = _emailRecipient;
    if (email == null) return;

    _goTo(SendStage.emailIntentPin);

    try {
      final model = ZendScope.of(context);
      final service = model.emailIntentService;
      if (service == null) {
        setState(() {
          _errorMessage = 'Email intent service not available.';
          _stage = SendStage.error;
        });
        return;
      }

      final result = await service.createIntent(
        recipientEmail: email,
        amountUsdc: widget.amount,
        pin: pin,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _emailIntentResult = result;
        _stage = SendStage.emailIntentSuccess;
      });

      unawaited(model.fetchBalance());
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
    } on PinDecryptionException {
      if (!mounted) return;
      _pinAttempts++;
      if (_pinAttempts >= 5) {
        setState(() {
          _errorMessage = 'Too many incorrect PIN attempts.';
          _stage = SendStage.error;
        });
      } else {
        _shakeController.forward(from: 0);
        setState(() {
          _pinDigits = '';
          _pinError = 'Incorrect PIN';
          _stage = SendStage.emailIntent;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = SendStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = SendStage.error;
      });
    }
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != SendStage.processing,
      child: AnimatedContainer(
          duration: _sheetResize,
          curve: Curves.easeOutCubic,
          height: screenHeight * _sheetHeightFraction,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZendRadii.xxl),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              const ZendSheetHandle(),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _stageTransition,
                  reverseDuration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: RepaintBoundary(child: _buildStageContent()),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case SendStage.recipient:
        return _RecipientStage(
          key: const ValueKey('recipient'),
          amount: widget.amount,
          amountFormatted: _amountFormatted,
          noteController: _noteController,
          prefilledRecipient: widget.prefilledRecipient,
          onConfirm: _onRecipientConfirmed,
          onEmailIntentSelected: _onEmailIntentSelected,
        );
      case SendStage.pin:
        return SendPinStage(
          key: const ValueKey('pin'),
          amountFormatted: _amountFormatted,
          recipientZendtag: _recipientZendtag ?? '',
          note: _noteController.text.trim(),
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: _onPinKey,
          onBack: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _stage = SendStage.recipient;
            });
          },
        );
      case SendStage.processing:
        return SendProcessingStage(
          key: const ValueKey('processing'),
          amountFormatted: _amountFormatted,
          recipientZendtag: _recipientZendtag ?? '',
        );
      case SendStage.success:
        return SendSuccessStage(
          key: const ValueKey('success'),
          amountFormattedExact: _amountFormattedExact,
          recipientZendtag: _recipientZendtag ?? '',
          onDone: _dismiss,
        );
      case SendStage.error:
        return SendErrorStage(
          key: const ValueKey('error'),
          errorMessage: _errorMessage ?? 'Something went wrong.',
          onRetry: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _stage = SendStage.pin;
            });
          },
          onCancel: _dismiss,
        );
      case SendStage.emailIntent:
        return _EmailIntentStage(
          key: const ValueKey('emailIntent'),
          email: _emailRecipient ?? '',
          amount: widget.amount,
          amountFormatted: _amountFormatted,
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: (value) {
            HapticFeedback.lightImpact();
            setState(() {
              _pinError = null;
              if (value == 'del') {
                if (_pinDigits.isNotEmpty) {
                  _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
                }
                return;
              }
              if (_pinDigits.length >= 4) return;
              _pinDigits += value;
            });
            if (_pinDigits.length == 4) {
              final pin = _pinDigits;
              _submitEmailIntentPin(pin);
            }
          },
          onBack: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _emailRecipient = null;
              _stage = SendStage.recipient;
            });
          },
        );
      case SendStage.emailIntentPin:
        return SendProcessingStage(
          key: const ValueKey('emailIntentPin'),
          amountFormatted: _amountFormatted,
          recipientZendtag: _maskEmail(_emailRecipient ?? ''),
        );
      case SendStage.emailIntentSuccess:
        return _EmailIntentSuccessStage(
          key: const ValueKey('emailIntentSuccess'),
          email: _emailRecipient ?? '',
          amountFormatted: _amountFormattedExact,
          intentResult: _emailIntentResult,
          onDone: _dismiss,
        );
    }
  }

  /// Masks an email address: first 2 chars of local part + *** + @domain.
  static String _maskEmail(String email) {
    final atIdx = email.indexOf('@');
    if (atIdx < 0) return email;
    final local = email.substring(0, atIdx);
    final domain = email.substring(atIdx); // includes '@'
    final prefix = local.length >= 2 ? local.substring(0, 2) : local;
    return '$prefix***$domain';
  }
}

// ── Recipient Stage ───────────────────────────────────────────────────────────

class _RecipientStage extends StatefulWidget {
  const _RecipientStage({
    super.key,
    required this.amount,
    required this.amountFormatted,
    required this.noteController,
    required this.onConfirm,
    required this.onEmailIntentSelected,
    this.prefilledRecipient,
  });

  final double amount;
  final String amountFormatted;
  final TextEditingController noteController;
  final String? prefilledRecipient;
  final void Function(String tag, String displayName) onConfirm;
  final void Function(String email) onEmailIntentSelected;

  @override
  State<_RecipientStage> createState() => _RecipientStageState();
}

class _RecipientStageState extends State<_RecipientStage> {
  late final TextEditingController _toController;
  final FocusNode _toFocus = FocusNode();
  final FocusNode _forFocus = FocusNode();

  String _toValue = '';
  bool _resolving = false;
  String? _resolveError;
  String? _resolvedDisplayName;
  String? _resolvedAvatarUrl;

  // ── Email intent detection ────────────────────────────────────────────────
  /// Set to true after zendtag resolution fails AND the input contains '@'.
  bool _showEmailOption = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(
      text: widget.prefilledRecipient ?? '',
    );
    _toValue = widget.prefilledRecipient ?? '';

    _forFocus.addListener(() {
      // No-op — keyboard visibility tracked via MediaQuery.viewInsets
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus && _toValue.isNotEmpty) {
        _resolveTag(_toValue);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _toController.dispose();
    _toFocus.dispose();
    _forFocus.dispose();
    super.dispose();
  }

  void _scheduleResolve(String raw) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _resolveTag(raw);
    });
  }

  Future<void> _resolveTag(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    // Determine whether this looks like an email (contains '@')
    final looksLikeEmail = trimmed.contains('@');

    // Strip leading '@' for zendtag resolution — but only if the value
    // does NOT look like an email (email addresses have '@' in the middle).
    final tag = looksLikeEmail
        ? trimmed.toLowerCase().replaceAll(RegExp(r'^@'), '')
        : trimmed.toLowerCase().replaceAll('@', '');

    if (tag.isEmpty) return;

    setState(() {
      _resolving = true;
      _resolveError = null;
      _resolvedDisplayName = null;
      _showEmailOption = false;
    });

    try {
      final model = ZendScope.of(context);
      final resolved = await model.zendtagService.resolve(tag);
      if (!mounted) return;
      setState(() {
        _resolvedDisplayName = resolved.displayName.trim().isNotEmpty
            ? resolved.displayName
            : '@${resolved.zendtag}';
        _resolvedAvatarUrl = resolved.avatarUrl;
        _resolving = false;
        _showEmailOption = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolveError = 'User not found';
        _resolving = false;
        // Show "Send via email" only when input contains '@' and resolution failed
        _showEmailOption = looksLikeEmail;
      });
    }
  }

  void _selectContact(RecentContact contact) {
    _debounceTimer?.cancel();
    _toController.text = contact.tag;
    _toValue = contact.tag;
    _resolvedDisplayName = contact.name;
    _resolvedAvatarUrl = contact.avatarUrl;
    _resolveError = null;
    _showEmailOption = false;
    _toFocus.unfocus();
    _forFocus.unfocus();
    setState(() {});
  }

  bool get _canPay {
    final model = ZendScope.of(context);
    final tag = _toValue.trim().replaceAll('@', '');
    return tag.isNotEmpty &&
        _resolveError == null &&
        !_resolving &&
        widget.amount > 0 &&
        widget.amount <= model.spendableBalance;
  }

  bool get _insufficientBalance {
    final model = ZendScope.of(context);
    return widget.amount > 0 && widget.amount > model.spendableBalance;
  }

  void _onPay() {
    if (!_canPay) return;
    final tag = _toValue.trim().replaceAll('@', '');
    final displayName = _resolvedDisplayName ?? '@$tag';
    widget.onConfirm(tag, displayName);
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final zt = ZendTheme.of(context);
    final recentContacts = model.recentContacts.take(15).toList();
    // Track keyboard visibility via MediaQuery — more reliable than focus listeners
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardHeight > 50;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false, // We handle keyboard offset manually
      body: Stack(
        children: [
          // ── Scrollable content ──────────────────────────────────────
          Positioned.fill(
            bottom: 72 + (keyboardOpen ? keyboardHeight : 0),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──────────────────────────────────────────
                  Text(
                    'Pay ${widget.amountFormatted}',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── To field ─────────────────────────────────────────
                  _FieldRow(
                    label: 'To',
                    child: TextField(
                      controller: _toController,
                      focusNode: _toFocus,
                      onChanged: (v) {
                        setState(() {
                          _toValue = v;
                          _resolvedDisplayName = null;
                          _resolveError = null;
                          _showEmailOption = false;
                        });
                        _scheduleResolve(v);
                      },
                      onSubmitted: (_) {
                        _debounceTimer?.cancel();
                        _resolveTag(_toValue);
                      },
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: '@username or email@domain.com',
                        hintStyle: TextStyle(color: zt.textSecondary),
                        // No border at all — we draw our own divider below
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                        // Constrained suffix so it doesn't blow out the row width
                        suffixIconConstraints: const BoxConstraints(
                          maxWidth: 24,
                          maxHeight: 24,
                        ),
                        suffixIcon: _resolving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: zt.textSecondary,
                                ),
                              )
                            : _resolvedDisplayName != null
                                ? Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                    color: zt.accentBright,
                                  )
                                : null,
                      ),
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),

                  // Resolved name or error
                  if (_resolvedDisplayName != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Row(
                        children: [
                          if (_resolvedAvatarUrl != null) ...[
                            ZendAvatar(
                              radius: 10,
                              photoUrl: _resolvedAvatarUrl,
                              initials: _resolvedDisplayName![0].toUpperCase(),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _resolvedDisplayName!,
                            style: TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 12,
                              color: zt.accentBright,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_resolveError != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Text(
                        _resolveError!,
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 12,
                          color: ZendColors.destructive,
                        ),
                      ),
                    ),
                    // ── "Send via email" option ───────────────────────────
                    if (_showEmailOption)
                      Padding(
                        padding: const EdgeInsets.only(left: 48, top: 8),
                        child: GestureDetector(
                          onTap: () {
                            widget.onEmailIntentSelected(_toValue.trim());
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: zt.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: zt.accent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.email_outlined,
                                  size: 14,
                                  color: zt.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Send via email',
                                  style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: zt.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],

                  const SizedBox(height: 4),
                  Divider(color: zt.border, height: 1),
                  const SizedBox(height: 4),

                  // ── For field ─────────────────────────────────────────
                  _FieldRow(
                    label: 'For',
                    child: TextField(
                      controller: widget.noteController,
                      focusNode: _forFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _forFocus.unfocus(),
                      decoration: InputDecoration(
                        hintText: 'optional',
                        hintStyle: TextStyle(color: zt.textSecondary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                      ),
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),
                  Divider(color: zt.border, height: 1),
                  const SizedBox(height: 20),

                  // ── Balance warning ───────────────────────────────────
                  if (_insufficientBalance)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Insufficient balance · \$${model.spendableBalance.toStringAsFixed(2)} available',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 12,
                          color: ZendColors.destructive,
                        ),
                      ),
                    ),

                  // ── Previous contacts ─────────────────────────────────
                  if (recentContacts.isNotEmpty && !keyboardOpen) ...[
                    Text(
                      'PREVIOUS',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: zt.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...recentContacts.map((contact) => _ContactTile(
                          contact: contact,
                          onTap: () => _selectContact(contact),
                        )),
                  ],
                ],
              ),
            ),
          ),

          // ── Pay button — always visible, floats above keyboard ──────
          Positioned(
            left: 20,
            right: 20,
            bottom: (keyboardOpen ? keyboardHeight : 0) + 16,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: PrimaryButton(
                label: 'Pay ${widget.amountFormatted}',
                onPressed: _canPay ? _onPay : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Field row (label + input) ─────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Contact tile ──────────────────────────────────────────────────────────────

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});

  final RecentContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final handle = '@${contact.tag}';
    // Show name if it's different from just the handle (i.e. a real display name exists)
    final hasRealName = contact.name.isNotEmpty &&
        contact.name != handle &&
        contact.name != contact.tag;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ZendAvatar(
              radius: 22,
              photoUrl: contact.avatarUrl,
              initials: contact.avatarLabel,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasRealName)
                    Text(
                      contact.name,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: zt.textPrimary,
                      ),
                    ),
                  Text(
                    handle,
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 12,
                      color: hasRealName ? zt.textSecondary : zt.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Email Intent Stage ────────────────────────────────────────────────────────

/// Stage that shows the masked email, amount, insufficient-balance guard,
/// and a PIN keypad to confirm the email intent creation.
class _EmailIntentStage extends StatelessWidget {
  const _EmailIntentStage({
    super.key,
    required this.email,
    required this.amount,
    required this.amountFormatted,
    required this.pinDigits,
    required this.pinError,
    required this.shakeAnimation,
    required this.shakeController,
    required this.onKey,
    required this.onBack,
  });

  final String email;
  final double amount;
  final String amountFormatted;
  final String pinDigits;
  final String? pinError;
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  /// Masks email: first 2 chars of local + *** + @domain.
  static String _mask(String e) {
    final atIdx = e.indexOf('@');
    if (atIdx < 0) return e;
    final local = e.substring(0, atIdx);
    final domain = e.substring(atIdx);
    final prefix = local.length >= 2 ? local.substring(0, 2) : local;
    return '$prefix***$domain';
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final zt = ZendTheme.of(context);
    final compact = MediaQuery.of(context).size.height < 760;
    final insufficientBalance = amount > model.spendableBalance;
    final maskedEmail = _mask(email);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          // ── Back arrow ──────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          // ── Recipient label ─────────────────────────────────────────
          Icon(Icons.email_outlined, color: zt.accent, size: 28),
          const SizedBox(height: 8),
          Text(
            maskedEmail,
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amountFormatted,
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // ── Insufficient balance error ───────────────────────────────
          if (insufficientBalance)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'Insufficient balance · \$${model.spendableBalance.toStringAsFixed(2)} available',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 12,
                  color: ZendColors.destructive,
                ),
              ),
            ),
          SizedBox(height: compact ? 16 : 24),
          // ── PIN dots with shake ─────────────────────────────────────
          if (!insufficientBalance) ...[
            AnimatedBuilder(
              animation: shakeController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: SendPinDots(filledCount: pinDigits.length),
            ),
            const SizedBox(height: 10),
            Text(
              pinError ?? 'Enter your PIN to confirm',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: pinError != null
                    ? ZendColors.destructive
                    : zt.textSecondary,
              ),
            ),
            const Spacer(),
            SendPinKeypad(
              onTap: onKey,
              keyHeight: compact ? 56 : 64,
            ),
            SizedBox(height: compact ? 4 : 12),
          ] else ...[
            const Spacer(),
          ],
        ],
      ),
    );
  }
}

// ── Email Intent Success Stage ────────────────────────────────────────────────

class _EmailIntentSuccessStage extends StatefulWidget {
  const _EmailIntentSuccessStage({
    super.key,
    required this.email,
    required this.amountFormatted,
    required this.intentResult,
    required this.onDone,
  });

  final String email;
  final String amountFormatted;
  final CreateIntentResult? intentResult;
  final VoidCallback onDone;

  @override
  State<_EmailIntentSuccessStage> createState() =>
      _EmailIntentSuccessStageState();
}

class _EmailIntentSuccessStageState extends State<_EmailIntentSuccessStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  /// Masks email: first 2 chars of local + *** + @domain.
  static String _mask(String e) {
    final atIdx = e.indexOf('@');
    if (atIdx < 0) return e;
    final local = e.substring(0, atIdx);
    final domain = e.substring(atIdx);
    final prefix = local.length >= 2 ? local.substring(0, 2) : local;
    return '$prefix***$domain';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final maskedEmail = _mask(widget.email);
    final result = widget.intentResult;

    // Compute days remaining from expiry
    int? daysRemaining;
    if (result != null) {
      final diff = result.expiry.difference(DateTime.now());
      daysRemaining = diff.isNegative ? 0 : diff.inDays;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: ZendColors.positive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sent!',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 36,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.amountFormatted} to $maskedEmail',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
            if (daysRemaining != null) ...[
              const SizedBox(height: 4),
              Text(
                'Expires in $daysRemaining day${daysRemaining == 1 ? '' : 's'}',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 12,
                  color: zt.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Done',
                onPressed: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
String _formatNgn(double value) {
  final rounded = value.round();
  final text = rounded.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final indexFromEnd = text.length - i;
    buffer.write(text[i]);
    if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
