import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

Future<void> showBotApprovalSheet(
  BuildContext context, {
  required String pairingCode,
}) {
  return showZendModalSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => BotApprovalSheet(pairingCode: pairingCode),
  );
}

enum _Stage { loading, review, working, done, denied, error }

/// Approves a new automated account that was started from the command line.
class BotApprovalSheet extends StatefulWidget {
  const BotApprovalSheet({super.key, required this.pairingCode});
  final String pairingCode;

  @override
  State<BotApprovalSheet> createState() => _BotApprovalSheetState();
}

class _BotApprovalSheetState extends State<BotApprovalSheet> {
  _Stage _stage = _Stage.loading;
  String? _sessionId;
  String _name = '';
  String _handle = '';
  List<String> _scopes = const [];
  String? _error;

  static const _scopeCopy = {
    'read': 'See its own profile and settings',
    'dm_send': 'Send messages',
    'post_card': 'Post to the feed',
    'send_money': 'Send money, within the limits you set',
    'receive_money': 'Receive money',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = ZendScope.read(context).walletService.apiClient;
      final s = await api.getBotSessionByCode(widget.pairingCode);
      if (!mounted) return;
      if (s['status'] != 'pending') {
        setState(() {
          _stage = _Stage.error;
          _error = s['status'] == 'expired'
              ? 'This request has expired. Start again from your computer.'
              : 'This request is no longer available.';
        });
        return;
      }
      setState(() {
        _sessionId = s['session_id'] as String;
        _name = s['bot_name'] as String? ?? '';
        _handle = s['handle'] as String? ?? '';
        _scopes = List<String>.from(s['scopes'] as List? ?? const []);
        _stage = _Stage.review;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = e.statusCode == 404
            ? 'This link isn\'t valid any more.'
            : e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = 'That didn\'t go through. Try again.';
      });
    }
  }

  Future<void> _approve() async {
    final model = ZendScope.of(context);
    if (!model.isZkLoginAccount) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Making bots isn\'t available for this kind of account yet.';
      });
      return;
    }
    setState(() => _stage = _Stage.working);
    try {
      await model.zkLoginService.satisfyStepUp();
      await model.walletService.apiClient.approveBotSession(_sessionId!);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _stage = _Stage.done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = 'Couldn\'t confirm it\'s you. Try again.';
      });
    }
  }

  Future<void> _deny() async {
    try {
      await ZendScope.read(context).walletService.apiClient.denyBotSession(
        _sessionId!,
      );
    } catch (_) {}
    if (mounted) setState(() => _stage = _Stage.denied);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
          height: 1.35,
        );

    Widget body;
    switch (_stage) {
      case _Stage.loading:
      case _Stage.working:
        body = const Center(child: ZendLoader(size: 32));
      case _Stage.review:
        body = Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Make this bot?',
                textAlign: TextAlign.center,
                style: s(26, w: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '$_name  @$_handle',
                textAlign: TextAlign.center,
                style: s(16, w: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'A bot is an account that code runs. People will see it marked as automated.',
                textAlign: TextAlign.center,
                style: s(13, c: zt.textSecondary),
              ),
              const SizedBox(height: 18),
              Text('It will be able to', style: s(13, w: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final sc in _scopes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsRegular.check,
                        size: 16,
                        color: zt.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _scopeCopy[sc] ?? sc,
                          style: s(13, c: zt.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              PrimaryButton(label: 'Make bot', onPressed: _approve),
              const SizedBox(height: 12),
              OutlineActionButton(label: 'Cancel', onPressed: _deny),
            ],
          ),
        );
      case _Stage.done:
        body = _message(zt, s, '@$_handle is ready', 'Go back to your computer to finish.');
      case _Stage.denied:
        body = _message(zt, s, 'Cancelled', null);
      case _Stage.error:
        body = _message(zt, s, _error ?? 'That didn\'t go through. Try again.', null);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _message(
    ZendTheme zt,
    TextStyle Function(double, {FontWeight w, Color? c}) s,
    String title,
    String? sub,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: s(20, w: FontWeight.w700)),
            if (sub != null) ...[
              const SizedBox(height: 8),
              Text(sub, textAlign: TextAlign.center, style: s(14, c: zt.textSecondary)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
