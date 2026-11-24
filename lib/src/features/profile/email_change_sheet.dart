import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

/// Changes where Zend sends notification email: enter the address, then the
/// 6-digit code sent to it. Resolves to the new settings, or null if cancelled.
Future<Map<String, dynamic>?> showEmailChangeSheet(BuildContext context) {
  return showZendModalSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => const _EmailChangeSheet(),
  );
}

class _EmailChangeSheet extends StatefulWidget {
  const _EmailChangeSheet();

  @override
  State<_EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends State<_EmailChangeSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String _messageFor(Object e) =>
      e is ZendException ? e.userMessage : "That didn't go through. Try again.";

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Check the email address');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ZendScope.of(
        context,
      ).walletService.apiClient.requestNotificationEmailChange(email);
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await ZendScope.of(
        context,
      ).walletService.apiClient.confirmNotificationEmailChange(code);
      if (mounted) Navigator.of(context).pop(settings);
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final style = TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textPrimary);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _codeSent ? 'Check your email' : 'Where should we email you?',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _codeSent
                ? 'We sent a 6-digit code to ${_email.text.trim()}. It expires in 10 minutes.'
                : "We'll send a code to make sure it's yours.",
            style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
          ),
          const SizedBox(height: 20),
          if (!_codeSent)
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _busy ? null : _sendCode(),
              style: style,
              decoration: const InputDecoration(labelText: 'Email'),
            )
          else
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _confirm(),
              style: style.copyWith(letterSpacing: 6, fontSize: 20),
              decoration: const InputDecoration(labelText: 'Code', counterText: ''),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.destructive),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : (_codeSent ? _confirm : _sendCode),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_codeSent ? 'Confirm' : 'Send code'),
            ),
          ),
          if (_codeSent)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _codeSent = false;
                      _code.clear();
                      _error = null;
                    }),
              child: const Text('Use a different email'),
            ),
        ],
      ),
    );
  }
}
