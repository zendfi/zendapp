import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

/// Opens the approval for `zdfi.me/bot-settings/{code}`: a change to one of your
/// bots, asked for from the command line, that lets it do more.
Future<void> showBotSettingsSheet(
  BuildContext context, {
  required String code,
}) {
  return showZendModalSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => BotSettingsSheet(code: code),
  );
}

enum _Stage { loading, review, working, done, denied, error }

class BotSettingsSheet extends StatefulWidget {
  const BotSettingsSheet({super.key, required this.code});
  final String code;

  @override
  State<BotSettingsSheet> createState() => _BotSettingsSheetState();
}

class _BotSettingsSheetState extends State<BotSettingsSheet> {
  _Stage _stage = _Stage.loading;
  String? _requestId;
  String _name = '';
  String _handle = '';
  List<String> _changes = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      _error = message;
    });
  }

  Future<void> _load() async {
    try {
      final api = ZendScope.read(context).walletService.apiClient;
      final r = await api.getBotSettingsRequestByCode(widget.code);
      if (!mounted) return;
      if (r['status'] != 'pending') {
        return _fail(
          r['status'] == 'expired'
              ? 'This request has expired. Run the command again.'
              : 'This request is no longer available.',
        );
      }
      final bot = Map<String, dynamic>.from(r['bot'] as Map? ?? const {});
      setState(() {
        _requestId = r['request_id'] as String;
        _name = bot['name'] as String? ?? '';
        _handle = bot['handle'] as String? ?? '';
        _changes = List<String>.from(r['changes'] as List? ?? const []);
        _stage = _Stage.review;
      });
    } on ApiException catch (e) {
      _fail(e.statusCode == 404 ? "This link isn't valid any more." : e.userMessage);
    } catch (_) {
      _fail("That didn't go through. Try again.");
    }
  }

  Future<void> _approve() async {
    final model = ZendScope.of(context);
    if (!model.isZkLoginAccount) {
      return _fail("Changing bots isn't available for this kind of account yet.");
    }
    setState(() => _stage = _Stage.working);
    try {
      await model.zkLoginService.satisfyStepUp();
      await model.walletService.apiClient.approveBotSettingsRequest(_requestId!);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _stage = _Stage.done);
    } on ApiException catch (e) {
      _fail(e.userMessage);
    } catch (_) {
      _fail("Couldn't confirm it's you. Try again.");
    }
  }

  Future<void> _deny() async {
    try {
      await ZendScope.read(context).walletService.apiClient.denyBotSettingsRequest(
        _requestId!,
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
                'Change this bot?',
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
                'Someone signed in as you asked for this from a computer. '
                'Only approve it if that was you.',
                textAlign: TextAlign.center,
                style: s(13, c: zt.textSecondary),
              ),
              const SizedBox(height: 18),
              Text('It will be able to', style: s(13, w: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final c in _changes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        PhosphorIconsRegular.arrowRight,
                        size: 16,
                        color: zt.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c, style: s(13, c: zt.textSecondary))),
                    ],
                  ),
                ),
              const Spacer(),
              PrimaryButton(label: 'Approve', onPressed: _approve),
              const SizedBox(height: 12),
              OutlineActionButton(label: 'Cancel', onPressed: _deny),
            ],
          ),
        );
      case _Stage.done:
        body = _message(zt, s, 'Done', '@$_handle has its new settings.');
      case _Stage.denied:
        body = _message(zt, s, 'Cancelled', 'Nothing changed.');
      case _Stage.error:
        body = _message(zt, s, _error ?? "That didn't go through. Try again.", null);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
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
              child: PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}
