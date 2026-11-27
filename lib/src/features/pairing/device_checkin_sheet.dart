import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

/// Someone scanned a device's check-in code (`zdfi.me/device-checkin/{code}`): a gym door, an
/// event gate, a class register. The device learns a code for this person, and their name only
/// if they turn it on. Nothing is paid.
Future<void> showDeviceCheckinSheet(BuildContext context, {required String code}) {
  return showZendModalSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CheckinSheet(code: code),
  );
}

enum _Stage { loading, review, working, done, error }

class _CheckinSheet extends StatefulWidget {
  const _CheckinSheet({required this.code});
  final String code;

  @override
  State<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends State<_CheckinSheet> {
  _Stage _stage = _Stage.loading;
  String _device = '';
  String? _owner;
  String? _note;
  bool _shareName = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _fail(String m) {
    if (mounted) setState(() => (_stage = _Stage.error, _error = m));
  }

  Future<void> _load() async {
    try {
      final v = await ZendScope.read(context).walletService.apiClient.getDeviceCheckin(widget.code);
      if (!mounted) return;
      if (v['status'] != 'waiting') {
        return _fail('This code was already used or has expired. Ask for a new one.');
      }
      setState(() {
        _device = v['device'] as String? ?? 'This device';
        _owner = v['owner'] as String?;
        _note = v['note'] as String?;
        _stage = _Stage.review;
      });
    } on ApiException catch (e) {
      _fail(e.statusCode == 404 ? "This code isn't valid any more." : e.userMessage);
    } catch (_) {
      _fail("That didn't go through. Try again.");
    }
  }

  Future<void> _confirm() async {
    setState(() => _stage = _Stage.working);
    try {
      await ZendScope.read(context).walletService.apiClient.confirmDeviceCheckin(widget.code, shareName: _shareName);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _stage = _Stage.done);
    } on ApiException catch (e) {
      _fail(e.userMessage);
    } catch (_) {
      _fail("That didn't go through. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontFamily: 'Geist', fontSize: size, fontWeight: w, color: c ?? zt.textPrimary, height: 1.35);
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
              Text('Check in?', textAlign: TextAlign.center, style: s(26, w: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(_note == null ? _device : '$_device · $_note', textAlign: TextAlign.center, style: s(16, w: FontWeight.w600)),
              if (_owner != null) ...[
                const SizedBox(height: 4),
                Text('Run by $_owner', textAlign: TextAlign.center, style: s(13, c: zt.textSecondary)),
              ],
              const SizedBox(height: 18),
              Text(
                "It gets a code for you, so it can tell when you're back. Not your number, @handle or balance. Nothing is paid.",
                style: s(13, c: zt.textSecondary),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareName,
                onChanged: (v) => setState(() => _shareName = v),
                title: Text('Share my name', style: s(14, w: FontWeight.w600)),
                subtitle: Text('So it can greet you', style: s(12, c: zt.textSecondary)),
              ),
              const Spacer(),
              PrimaryButton(label: 'Check in', onPressed: _confirm),
              const SizedBox(height: 12),
              OutlineActionButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        );
      case _Stage.done:
        body = _msg(s, "You're checked in", _device);
      case _Stage.error:
        body = _msg(s, _error ?? "That didn't go through. Try again.", null);
    }
    return Container(
      height: MediaQuery.of(context).size.height * 0.62,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Column(children: [const SizedBox(height: 14), const ZendSheetHandle(), const SizedBox(height: 8), Expanded(child: body)]),
    );
  }

  Widget _msg(TextStyle Function(double, {FontWeight w, Color? c}) s, String title, String? sub) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, textAlign: TextAlign.center, style: s(20, w: FontWeight.w700)),
              if (sub != null) ...[const SizedBox(height: 8), Text(sub, textAlign: TextAlign.center, style: s(14))],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop())),
            ],
          ),
        ),
      );
}
