import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/recent_contact.dart';
import '../../services/sound_service.dart';
import 'bank_send_sheet.dart';
import 'crypto_send_sheet.dart';
import 'send_shared_widgets.dart';

enum SendStage { recipient, note, pin, processing, success, error }

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
  // ignore: unused_field
  String? _recipientWalletAddress;

  final _noteController = TextEditingController();

  double? _fxPreviewNgn;

  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

  String? _errorMessage;
  // ignore: unused_field
  String? _transferResult; // tx signature on success

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  bool _resolving = false;

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
      _recipientDisplayName = '@${widget.prefilledRecipient}';
      _stage = SendStage.note;
      if (widget.prefilledNote != null) {
        _noteController.text = widget.prefilledNote!;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchFxPreview());
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
        return 0.92;
      case SendStage.note:
        return 0.65;
      case SendStage.pin:
        return 0.70;
      case SendStage.processing:
        return 0.45;
      case SendStage.success:
        return 0.50;
      case SendStage.error:
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

  Future<void> _onContactTap(String tag, String displayName) async {
    if (_resolving) return;
    setState(() => _resolving = true);

    try {
      final model = ZendScope.of(context);
      final resolved = await model.zendtagService.resolve(tag);
      if (!mounted) return;
      setState(() {
        _recipientZendtag = resolved.zendtag;
        _recipientDisplayName = resolved.displayName;
        _recipientWalletAddress = resolved.walletAddress;
        _resolving = false;
        _stage = SendStage.note;
      });
      _fetchFxPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      setState(() {
        _recipientZendtag = tag;
        _recipientDisplayName = displayName;
        _recipientWalletAddress = null;
        _stage = SendStage.note;
      });
      _fetchFxPreview();
    }
  }

  Future<void> _fetchFxPreview() async {
    try {
      final model = ZendScope.of(context);
      final preview = await model.fxService.getPreview(widget.amount);
      if (!mounted) return;
      setState(() => _fxPreviewNgn = preview.amountNgn);
    } catch (_) {
      // Silently ignore, cos FX preview is optional
    }
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
      final result = await model.transferService.sendTransfer(
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
        _transferResult = result.transactionSignature;
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

  void _dismiss() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != SendStage.processing,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
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
          resolving: _resolving,
          onContactTap: _onContactTap,
        );
      case SendStage.note:
        return _NoteStage(
          key: const ValueKey('note'),
          amountFormatted: _amountFormatted,
          recipientName: _recipientDisplayName ?? '',
          noteController: _noteController,
          fxPreviewNgn: _fxPreviewNgn,
          onBack: () {
            setState(() {
              _stage = SendStage.recipient;
              _fxPreviewNgn = null;
            });
          },
          onConfirm: () => _goTo(SendStage.pin),
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
              _stage = SendStage.note;
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
    }
  }
}

class _RecipientStage extends StatefulWidget {
  const _RecipientStage({
    super.key,
    required this.amount,
    required this.amountFormatted,
    required this.resolving,
    required this.onContactTap,
  });

  final double amount;
  final String amountFormatted;
  final bool resolving;
  final Future<void> Function(String tag, String displayName) onContactTap;

  @override
  State<_RecipientStage> createState() => _RecipientStageState();
}

class _RecipientStageState extends State<_RecipientStage> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  List<(String name, String tag, String avatar)> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _searchQuery = query);

    final normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    final searchTag = normalized.startsWith('@')
        ? normalized.substring(1)
        : normalized;

    if (searchTag.length < 3) {
      setState(() => _searching = false);
      return;
    }

    setState(() => _searching = true);

    try {
      final model = ZendScope.of(context);
      final resolved = await model.zendtagService.resolve(searchTag);
      if (!mounted) return;

      final displayName = resolved.displayName.trim().isEmpty
          ? '@${resolved.zendtag}'
          : resolved.displayName;
      final avatarLabel = displayName.isNotEmpty
          ? displayName[0].toUpperCase()
          : resolved.zendtag.isNotEmpty
              ? resolved.zendtag[0].toUpperCase()
              : '?';

      setState(() {
        _searchResults = [
          (displayName, resolved.zendtag, avatarLabel),
        ];
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final recentContacts = _buildRecentContacts(model.recentContacts);
    
    final contactsToShow = _searchQuery.isNotEmpty ? _searchResults : recentContacts;
    final showingSearchResults = _searchQuery.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pay ${widget.amountFormatted} to',
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Name, @username, phone...',
              prefixIcon: const Icon(Icons.search,
                  size: 20, color: ZendColors.textSecondary),
              filled: true,
              fillColor: ZendColors.bgSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZendRadii.pill),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            showingSearchResults ? 'SEARCH RESULTS' : 'RECENT ZEND USERS',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: ZendColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Contact list
          if (widget.resolving || _searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: ZendLoader(size: 24)),
            )
          else if (contactsToShow.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                showingSearchResults
                    ? 'No users found with that zendtag'
                    : 'No recent recipients yet',
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.textSecondary,
                ),
              ),
            )
          else
            ...List.generate(contactsToShow.length, (i) {
              final (name, tag, avatar) = contactsToShow[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ContactTile(
                  name: name,
                  handle: '@$tag',
                  avatarLabel: avatar,
                  onTap: () => widget.onContactTap(tag, name),
                ),
              );
            }),
          const SizedBox(height: 18),
          Text(
            'EXTERNAL',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: ZendColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              if (widget.amount <= 0) {
                // Amount not set — close this sheet and let the user enter
                // an amount on the keypad first. The send screen's Pay button
                // already guards against 0, so this handles edge cases like
                // deep-link opens with no amount.
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop();
              showBankSendSheet(context, amount: widget.amount);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ZendColors.bgPrimary,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ZendColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ZendColors.bgSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_outlined),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send to bank account',
                            style: TextStyle(fontSize: 15)),
                        SizedBox(height: 2),
                        Text(
                          'Nigeria, UK, USA, Europe',
                          style: TextStyle(
                              fontSize: 12, color: ZendColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: ZendColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              if (widget.amount <= 0) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop();
              showCryptoSendSheet(context, amount: widget.amount);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ZendColors.bgPrimary,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ZendColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ZendColors.bgSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.currency_bitcoin_outlined),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send to crypto wallet',
                            style: TextStyle(fontSize: 15)),
                        SizedBox(height: 2),
                        Text(
                          'Any chain — Tron, Ethereum, BNB...',
                          style: TextStyle(
                              fontSize: 12, color: ZendColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: ZendColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<(String name, String tag, String avatar)> _buildRecentContacts(
  List<RecentContact> contacts,
) {
  return contacts
      .take(5)
      .map((contact) => (contact.name, contact.tag, contact.avatarLabel))
      .toList();
}

class _NoteStage extends StatelessWidget {
  const _NoteStage({
    super.key,
    required this.amountFormatted,
    required this.recipientName,
    required this.noteController,
    required this.fxPreviewNgn,
    required this.onBack,
    required this.onConfirm,
  });

  final String amountFormatted;
  final String recipientName;
  final TextEditingController noteController;
  final double? fxPreviewNgn;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back,
                  color: ZendColors.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Pay $amountFormatted to ',
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ZendColors.textPrimary,
                  ),
                ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: ZendColors.bgSecondary,
                      child: Text(
                        recipientName.isNotEmpty
                            ? recipientName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 11, color: ZendColors.textPrimary),
                      ),
                    ),
                  ),
                ),
                TextSpan(
                  text: '$recipientName for',
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ZendColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Note text field
          TextField(
            controller: noteController,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: "What's it for?",
              filled: false,
              border: InputBorder.none,
            ),
            style: const TextStyle(
                fontSize: 18, color: ZendColors.textPrimary),
          ),
          const SizedBox(height: 16),
          // FX preview
          if (fxPreviewNgn != null)
            Text(
              '≈ ₦${_formatNgn(fxPreviewNgn!)}',
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 14,
                color: ZendColors.textSecondary,
              ),
            ),
          const Spacer(),
          PrimaryButton(
            label: 'Zend $amountFormatted',
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.name,
    required this.handle,
    required this.avatarLabel,
    required this.onTap,
  });

  final String name;
  final String handle;
  final String avatarLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: ZendColors.bgSecondary,
              child: Text(avatarLabel,
                  style: const TextStyle(color: ZendColors.textPrimary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    handle,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 13,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: ZendColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

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
