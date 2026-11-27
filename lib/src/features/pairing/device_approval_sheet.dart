import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

/// Opens the sheet for a device that's waiting to be added. [code] is the long code from the
/// device's QR (`zdfi.me/device-auth/{code}`); leave it null to type the 6 characters it shows.
Future<bool?> showDeviceApprovalSheet(BuildContext context, {String? code}) {
  return showZendModalSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => DeviceApprovalSheet(code: code),
  );
}

enum _Stage { entry, loading, review, working, done, denied, error }

/// Adds an ESP32, Arduino or Raspberry Pi to the person's account. A device only asks for
/// payments; what people pay lands in this person's balance.
class DeviceApprovalSheet extends StatefulWidget {
  const DeviceApprovalSheet({super.key, this.code});

  final String? code;

  @override
  State<DeviceApprovalSheet> createState() => _DeviceApprovalSheetState();
}

class _DeviceApprovalSheetState extends State<DeviceApprovalSheet> {
  late _Stage _stage = widget.code == null ? _Stage.entry : _Stage.loading;
  final _codeCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  String? _sessionId;
  String? _hardware;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(widget.code!));
    }
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      _error = message;
    });
  }

  Future<void> _load(String code) async {
    setState(() => _stage = _Stage.loading);
    try {
      final api = ZendScope.read(context).walletService.apiClient;
      final s = await api.getDeviceSessionByCode(code.trim());
      if (!mounted) return;
      if (s['status'] != 'pending') {
        return _fail(
          s['status'] == 'expired'
              ? 'This code has expired. Restart the device to get a new one.'
              : 'This code is no longer available.',
        );
      }
      setState(() {
        _sessionId = s['session_id'] as String;
        _nameCtl.text = s['name'] as String? ?? '';
        _hardware = s['hardware'] as String?;
        _stage = _Stage.review;
      });
    } on ApiException catch (e) {
      _fail(e.statusCode == 404 ? "That code isn't valid. Check the device's screen." : e.userMessage);
    } catch (_) {
      _fail("That didn't go through. Try again.");
    }
  }

  Future<void> _approve() async {
    final model = ZendScope.of(context);
    setState(() => _stage = _Stage.working);
    try {
      await model.walletService.apiClient.approveDeviceSession(
        _sessionId!,
        name: _nameCtl.text.trim().isEmpty ? null : _nameCtl.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _stage = _Stage.done);
    } on ApiException catch (e) {
      _fail(e.userMessage);
    } catch (_) {
      _fail("That didn't go through. Try again.");
    }
  }

  Future<void> _deny() async {
    try {
      await ZendScope.read(context).walletService.apiClient.denyDeviceSession(_sessionId!);
    } catch (_) {}
    if (mounted) setState(() => _stage = _Stage.denied);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) => TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
          height: 1.35,
        );
    InputDecoration field(String hint) => InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

    Widget bullet(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: zt.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: s(13, c: zt.textSecondary))),
            ],
          ),
        );

    Widget body;
    switch (_stage) {
      case _Stage.loading:
      case _Stage.working:
        body = const Center(child: ZendLoader(size: 32));
      case _Stage.entry:
        body = Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a device', textAlign: TextAlign.center, style: s(26, w: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Type the 6 characters on the device\'s screen, or scan its code from the Scan button.',
                textAlign: TextAlign.center,
                style: s(13, c: zt.textSecondary),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _codeCtl,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: s(24, w: FontWeight.w600).copyWith(letterSpacing: 6),
                decoration: field('ABC234'),
                onChanged: (_) => setState(() {}),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Continue',
                onPressed: _codeCtl.text.trim().length == 6 ? () => _load(_codeCtl.text) : null,
              ),
            ],
          ),
        );
      case _Stage.review:
        body = Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add this device?', textAlign: TextAlign.center, style: s(26, w: FontWeight.w700)),
              if (_hardware != null) ...[
                const SizedBox(height: 4),
                Text(_hardware!, textAlign: TextAlign.center, style: s(13, c: zt.textSecondary)),
              ],
              const SizedBox(height: 16),
              Text('Name', style: s(13, w: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(controller: _nameCtl, maxLength: 40, decoration: field('Laundry, machine 3')),
              const SizedBox(height: 4),
              Text('It will be able to', style: s(13, w: FontWeight.w600)),
              const SizedBox(height: 4),
              bullet(PhosphorIconsRegular.qrCode, 'Ask people to pay you, up to ₦20,000 at a time'),
              bullet(PhosphorIconsRegular.bellRinging, 'Know when a payment reaches you'),
              const SizedBox(height: 8),
              Text('It can never', style: s(13, w: FontWeight.w600)),
              const SizedBox(height: 4),
              bullet(PhosphorIconsRegular.prohibit, 'Send money, or see your balance'),
              const SizedBox(height: 6),
              Text(
                'Payments go straight to your Zend. You can pause or remove it any time in Settings → Devices.',
                style: s(12, c: zt.textSecondary),
              ),
              const Spacer(),
              PrimaryButton(label: 'Add device', onPressed: _approve),
              const SizedBox(height: 12),
              OutlineActionButton(label: 'Cancel', onPressed: _deny),
            ],
          ),
        );
      case _Stage.done:
        body = _message(zt, s, '${_nameCtl.text.trim()} is ready', 'The device will finish setting up on its own.', ok: true);
      case _Stage.denied:
        body = _message(zt, s, 'Cancelled', null);
      case _Stage.error:
        body = _message(zt, s, _error ?? "That didn't go through. Try again.", null);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
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
    String? sub, {
    bool ok = false,
  }) {
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
              child: PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop(ok)),
            ),
          ],
        ),
      ),
    );
  }
}
