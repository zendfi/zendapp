import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_format.dart';
import '../../core/zend_state.dart';
import '../../design/zend_keypad.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/offline_pay_service.dart';

/// Shown only in builds made with `--dart-define=ZEND_OFFLINE_TEST=true`.
const bool kOfflinePayTest = bool.fromEnvironment('ZEND_OFFLINE_TEST');

/// Test screen for paying without signal (R21, task 0.9). See
/// `.kiro/specs/appkit-primitives/offline-test.md` for the two-phone steps.
class OfflinePayScreen extends StatefulWidget {
  const OfflinePayScreen({super.key});

  @override
  State<OfflinePayScreen> createState() => _OfflinePayScreenState();
}

class _OfflinePayScreenState extends State<OfflinePayScreen> {
  late final OfflinePayService _svc;
  bool _busy = false;
  String? _message;
  String? _receiveCode;
  String? _paymentCode;
  ReceiveCode? _payee;
  final _amount = TextEditingController();
  final AmountEntry _entry = AmountEntry.current();
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final model = ZendScope.of(context);
    _svc = OfflinePayService(
      api: model.walletService.apiClient,
      zkLogin: model.zkLoginService,
    );
    _tick ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await f();
    } on OfflinePayException catch (e) {
      _message = e.message;
    } catch (e) {
      _message = 'That didn\'t go through: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _getReady() => _run(() async {
    final model = ZendScope.of(context);
    final until = await _svc.getReady();
    _receiveCode = _svc.receiveCode(
      username: model.zendtagIsPlaceholder ? null : model.currentZendtag,
      name: model.currentDisplayName,
    );
    _message = 'Ready. Keep Zend open. Works until ${formatDateTime(until)}.';
  });

  Future<String?> _scan(String title) => Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => _ScanPage(title: title)));

  Future<void> _scanPayee() async {
    final raw = await _scan("Scan the other person's receive code");
    if (raw == null) return;
    final code = OfflinePayService.readReceiveCode(raw);
    setState(() {
      _payee = code;
      _paymentCode = null;
      _message = code == null ? "That isn't a Zend receive code" : null;
    });
  }

  Future<void> _pay() => _run(() async {
    final usd = _entry.usd(_amount.text);
    _paymentCode = await _svc.pay(_payee!, usd);
    _message = 'Signed with no signal. Show this to ${_payee!.label}.';
  });

  Future<void> _collect([String? pasted]) async {
    final model = ZendScope.of(context);
    final raw = pasted ?? await _scan('Scan the payment code');
    if (raw == null) return;
    await _run(() async {
      final r = await _svc.collect(raw);
      final usd = (r['amount_usd'] as num?)?.toDouble() ?? 0;
      _message =
          'Received ${formatMoney(usd)}${r['from'] != null ? ' from @${r['from']}' : ''}.';
      unawaited(model.fetchBalance());
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final until = _svc.readyUntil;
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    Widget qr(String data) => Center(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: QrImageView(
          data: data,
          size: 280,
          errorCorrectionLevel: QrErrorCorrectLevel.L,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Pay without signal (test)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            until == null
                ? 'Not ready. While you have signal, tap Get ready, then keep Zend open.'
                : 'Ready until ${formatDateTime(until)}. Keep Zend open.',
            style: s(14, c: zt.textSecondary),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: until == null ? 'Get ready' : 'Get ready again',
            isLoading: _busy && until == null,
            onPressed: _busy ? null : _getReady,
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: s(14, w: FontWeight.w600)),
          ],
          const Divider(height: 36),
          Text('Receive', style: s(17, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Show this to the person paying you.',
            style: s(13, c: zt.textSecondary),
          ),
          const SizedBox(height: 10),
          if (_receiveCode != null)
            qr(_receiveCode!)
          else
            Text(
              'Tap Get ready to make your code.',
              style: s(13, c: zt.textSecondary),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : () => _collect(),
            child: const Text('Scan a payment code (needs signal)'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final t = (await Clipboard.getData('text/plain'))?.text;
                    if (t != null && OfflinePayService.isPaymentCode(t)) {
                      await _collect(t);
                    }
                  },
            child: const Text('Paste a payment code'),
          ),
          const Divider(height: 36),
          Text('Pay', style: s(17, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Works in airplane mode.', style: s(13, c: zt.textSecondary)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : _scanPayee,
            child: Text(
              _payee == null
                  ? 'Scan their receive code'
                  : 'Paying ${_payee!.label} (scan again)',
            ),
          ),
          if (_payee != null) ...[
            TextField(
              controller: _amount,
              inputFormatters: [AmountInputFormatter(naira: _entry.naira)],
              keyboardType: TextInputType.numberWithOptions(
                decimal: !_entry.naira,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: _entry.symbol,
              ),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Sign payment',
              isLoading: _busy,
              onPressed: _busy ? null : _pay,
            ),
          ],
          if (_paymentCode != null) ...[
            const SizedBox(height: 16),
            qr(_paymentCode!),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Share.share(_paymentCode!),
              child: const Text('Share the code instead'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage({required this.title});
  final String title;
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    returnImage: false,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        final v = capture.barcodes.firstOrNull?.rawValue;
        if (v == null || _done) return;
        _done = true;
        Navigator.of(context).pop(v);
      },
    ),
  );
}
