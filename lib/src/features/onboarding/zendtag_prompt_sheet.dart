import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

/// Offers a zendtag to a user whose handle is still their email address.
///
/// Deliberately not a gate. The account already works — it can send, receive, and
/// be paid — so every exit from this sheet is valid:
///
///   * claim a handle,
///   * "Maybe later", which asks again next time,
///   * "Don't ask again", which makes the email the permanent handle.
///
/// That last option is recorded server-side rather than in device preferences, so
/// a reinstall or a second device does not re-ask someone who already declined.
Future<void> showZendtagPromptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Dismissible on purpose: closing it is the same as "maybe later".
    builder: (_) => const _ZendtagPromptSheet(),
  );
}

class _ZendtagPromptSheet extends StatefulWidget {
  const _ZendtagPromptSheet();

  @override
  State<_ZendtagPromptSheet> createState() => _ZendtagPromptSheetState();
}

class _ZendtagPromptSheetState extends State<_ZendtagPromptSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  bool _checking = false;
  bool? _available;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Mirrors the format the backend enforces, so an obviously invalid handle
  /// never costs a round-trip. The server remains the authority.
  String? _formatError(String tag) {
    if (tag.length < 3 || tag.length > 20) {
      return 'Between 3 and 20 characters';
    }
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(tag)) {
      return 'Letters, numbers, dots and underscores only';
    }
    if (tag.startsWith('.') ||
        tag.startsWith('_') ||
        tag.endsWith('.') ||
        tag.endsWith('_')) {
      return 'Cannot start or end with a dot or underscore';
    }
    return null;
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final tag = raw.trim().toLowerCase();
    setState(() {
      _available = null;
      _error = null;
      _checking = false;
    });
    if (tag.isEmpty) return;
    if (_formatError(tag) != null) return;

    setState(() => _checking = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final available = await ZendScope.read(
          context,
        ).zendtagService.checkAvailability(tag);
        if (!mounted || _controller.text.trim().toLowerCase() != tag) return;
        setState(() {
          _available = available;
          _checking = false;
        });
      } catch (_) {
        if (!mounted) return;
        // A failed lookup must not read as "taken" — leave it unknown and let
        // the claim attempt be the authority.
        setState(() => _checking = false);
      }
    });
  }

  Future<void> _claim() async {
    final tag = _controller.text.trim().toLowerCase();
    final formatError = _formatError(tag);
    if (formatError != null) {
      setState(() => _error = formatError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final model = ZendScope.read(context);
    final navigator = Navigator.of(context);
    try {
      final claimed = await model.walletService.apiClient.claimZendtag(tag);
      if (!mounted) return;
      model.applyClaimedZendtag(claimed);
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _busy = false;
        // The server just told us it is unavailable, so stop showing it as free.
        if (e.errorCode == 'ZENDTAG_UNAVAILABLE' ||
            e.errorCode == 'ZENDTAG_RESERVED') {
          _available = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't claim that handle. Please try again.";
        _busy = false;
      });
    }
  }

  Future<void> _neverAskAgain() async {
    setState(() => _busy = true);
    final model = ZendScope.read(context);
    final navigator = Navigator.of(context);
    try {
      await model.walletService.apiClient.suppressZendtagPrompt();
    } catch (_) {
      // Non-fatal: the worst case is being asked again next sign-in, which is
      // better than blocking the user inside a sheet they asked to leave.
    }
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final tag = _controller.text.trim().toLowerCase();
    final formatError = tag.isEmpty ? null : _formatError(tag);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.lg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: zt.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Want a zendtag?',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a short handle so you can send and receive cash without '
                'sharing your email.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: zt.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_busy,
                onChanged: _onChanged,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _claim(),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(20),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                ],
                style: TextStyle(color: zt.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  prefixText: 'zdfi.me/@',
                  prefixStyle: TextStyle(color: zt.textSecondary, fontSize: 16),
                  hintText: 'yourname',
                  hintStyle: TextStyle(color: zt.textSecondary),
                  suffixIcon: _checking
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _available == true
                      ? Icon(Icons.check, color: zt.accent)
                      : _available == false
                      ? const Icon(
                          Icons.close,
                          color: ZendColors.destructive,
                        )
                      : null,
                ),
              ),
              if (formatError != null || _error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error ?? formatError!,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: ZendColors.destructive,
                  ),
                ),
              ] else if (_available == false) ...[
                const SizedBox(height: 8),
                const Text(
                  'That handle is taken',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: ZendColors.destructive,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Claim handle',
                isLoading: _busy,
                onPressed: tag.isEmpty || formatError != null ? null : _claim,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(
                  'Maybe later',
                  style: TextStyle(color: zt.textSecondary),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _neverAskAgain,
                child: Text(
                  "Don't ask again — use my email",
                  style: TextStyle(
                    color: zt.textSecondary.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
