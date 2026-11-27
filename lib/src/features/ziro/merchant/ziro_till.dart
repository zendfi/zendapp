/// The till (R5, design §5.3): amount → customer view → colour flash → PIN when
/// asked → Paid. The phone faces the customer from "Charge" until "Paid".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:ziro_vision/ziro_vision.dart';

import '../../../core/zend_format.dart' show DisplayCurrency;
import '../../../design/zend_primitives.dart';
import '../../../design/zend_tokens.dart';
import '../shared/ziro_copy.dart';
import '../shared/ziro_models.dart';
import '../shared/ziro_pin_pad.dart';
import '../shared/ziro_service.dart';
import 'ziro_activity.dart';

enum _Step { amount, starting, palm, flash, checking, pin, settling, paid, notFound, failed }

class ZiroTill extends StatefulWidget {
  const ZiroTill({super.key, required this.svc, required this.merchant, required this.device, required this.config});
  final ZiroService svc;
  final ZiroMerchant merchant;
  final ZiroDeviceRecord device;
  final ZiroConfig config;

  @override
  State<ZiroTill> createState() => _ZiroTillState();
}

class _ZiroTillState extends State<ZiroTill> {
  _Step _step = _Step.amount;
  String _amount = '';
  String _guide = ZiroCopy.holdPalm;
  String _message = '';
  Color _flash = Colors.white;
  ZiroCharge? _charge;
  ZiroChallenge? _challenge;
  ZiroPinRequired? _pinAsk;
  ZiroSettled? _settled;
  int _scans = 0;
  StreamSubscription<ZiroVisionEvent>? _sub;
  final _pinKey = GlobalKey<ZiroPinPadState>();

  String get _currency => DisplayCurrency.isNaira ? 'NGN' : 'USD';
  ZiroService get _svc => widget.svc;

  @override
  void dispose() {
    _sub?.cancel();
    _svc.vision.stopCapture().ignore();
    WakelockPlus.disable().ignore();
    super.dispose();
  }

  // ===================== amount =====================

  void _key(String k) {
    setState(() {
      if (k == '<') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (k == '.') {
        if (_currency == 'USD' && !_amount.contains('.')) _amount = _amount.isEmpty ? '0.' : '$_amount.';
      } else {
        final dot = _amount.indexOf('.');
        if (dot >= 0 && _amount.length - dot > 2) return;
        if (_amount.length >= 9) return;
        _amount = _amount == '0' ? k : '$_amount$k';
      }
    });
  }

  String get _amountShown {
    final symbol = _currency == 'NGN' ? '₦' : r'$';
    return '$symbol${_amount.isEmpty ? '0' : _amount}';
  }

  // ===================== charge =====================

  Future<void> _charge_() async {
    setState(() => _step = _Step.starting);
    try {
      await WakelockPlus.enable();
      final charge = await _svc.api.createCharge(deviceId: widget.device.deviceId, currency: _currency, value: _amount);
      final ch = await _svc.challenge(charge, widget.device, widget.merchant.payoutAddress);
      _charge = charge;
      _challenge = ch;
      _scans = 0;
      await _startCapture();
    } catch (e) {
      _fail(ziroErrorText(e));
    }
  }

  Future<void> _startCapture() async {
    final ch = _challenge!;
    _sub?.cancel();
    _sub = _svc.vision.events.listen(_onEvent);
    setState(() {
      _step = _Step.palm;
      _guide = ZiroCopy.holdPalm;
    });
    await _svc.vision.startCapture(mode: CaptureMode.pay, colours: ch.colours, colourMs: ch.colourMs, timeout: const Duration(seconds: 25));
  }

  void _onEvent(ZiroVisionEvent e) {
    switch (e) {
      case GuideEvent(:final rawCode):
        if (_step == _Step.palm) setState(() => _guide = ziroGuideCopy(rawCode));
      case ReadyForFlashEvent():
        _runFlash();
      case CapturedEvent():
        _scan(e);
      case ErrorEvent(:final rawCode):
        _fail(ziroCameraErrorCopy(rawCode));
      default:
        break;
    }
  }

  Future<void> _paint(Color c) async {
    setState(() => _flash = c);
    await WidgetsBinding.instance.endOfFrame;
  }

  /// White first (the neutral reference), then each colour for its slot, telling the
  /// plugin right after each paint so it can line frames up with colours.
  Future<void> _runFlash() async {
    final ch = _challenge!;
    setState(() => _step = _Step.flash);
    await _paint(Colors.white);
    await _svc.vision.flashShown(-1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    for (var i = 0; i < ch.colours.length; i++) {
      await _paint(_hex(ch.colours[i]));
      await _svc.vision.flashShown(i);
      await Future<void>.delayed(Duration(milliseconds: ch.colourMs));
    }
    await _paint(Colors.white);
    if (mounted && _step == _Step.flash) setState(() => _step = _Step.checking);
  }

  static Color _hex(String h) => Color(0xFF000000 | int.parse(h.substring(1), radix: 16));

  Future<void> _scan(CapturedEvent cap) async {
    setState(() => _step = _Step.checking);
    _scans++;
    try {
      final r = await _svc.scan(_charge!, widget.device, _challenge!, cap);
      await _handle(r);
    } catch (e) {
      _fail(ziroErrorText(e));
    }
  }

  Future<void> _handle(ZiroScanResult r) async {
    switch (r) {
      case ZiroApproved(:final approval):
        await _settle(approval);
      case ZiroPinRequired():
        setState(() {
          _pinAsk = r;
          _message = '';
          _step = _Step.pin;
        });
      case ZiroNotFound(:final retryAllowed):
        if (retryAllowed && _scans < 2) {
          await _startCapture();
        } else {
          setState(() => _step = _Step.notFound);
        }
      case ZiroPinWrong(:final attemptsLeft):
        HapticFeedback.heavyImpact();
        _pinKey.currentState?.reshuffle();
        setState(() => _message = ZiroCopy.pinWrong(attemptsLeft));
      case ZiroRefused(:final code, :final message):
        _fail(ziroRefusedCopy(code, message));
    }
  }

  Future<void> _pin(String pin) async {
    final ask = _pinAsk;
    if (ask == null) return;
    setState(() => _step = _Step.checking);
    try {
      final r = await _svc.pin(_charge!, widget.device, _challenge!, ask.scanId, pin);
      if (r is ZiroPinWrong) setState(() => _step = _Step.pin);
      await _handle(r);
    } catch (e) {
      _fail(ziroErrorText(e));
    }
  }

  Future<void> _settle(ZiroApproval a) async {
    setState(() => _step = _Step.settling);
    try {
      final s = await _svc.api.settle(_charge!.chargeId, a);
      if (widget.merchant.haptics) HapticFeedback.mediumImpact();
      if (widget.merchant.sound) SystemSound.play(SystemSoundType.click);
      setState(() {
        _settled = s;
        _step = _Step.paid;
      });
    } catch (e) {
      _fail(ziroErrorText(e));
    } finally {
      WakelockPlus.disable().ignore();
    }
  }

  void _fail(String msg) {
    _svc.vision.stopCapture().ignore();
    WakelockPlus.disable().ignore();
    if (!mounted) return;
    setState(() {
      _message = msg;
      _step = _Step.failed;
    });
  }

  Future<void> _cancel() async {
    final c = _charge;
    _sub?.cancel();
    await _svc.vision.stopCapture();
    WakelockPlus.disable().ignore();
    if (c != null && _step != _Step.paid && _step != _Step.settling) {
      _svc.api.cancelCharge(c.chargeId).ignore();
    }
    _reset();
  }

  void _reset() {
    setState(() {
      _step = _Step.amount;
      _amount = '';
      _charge = null;
      _challenge = null;
      _pinAsk = null;
      _settled = null;
      _message = '';
    });
  }

  // ===================== views =====================

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    if (_step == _Step.flash) {
      return ColoredBox(color: _flash, child: const SizedBox.expand());
    }
    final customerFacing = _step != _Step.amount;
    return Scaffold(
      backgroundColor: customerFacing ? Colors.black : zt.bgPrimary,
      appBar: customerFacing
          ? null
          : AppBar(
              backgroundColor: zt.bgPrimary,
              elevation: 0,
              title: Text(widget.merchant.businessName, style: TextStyle(color: zt.textPrimary)),
              iconTheme: IconThemeData(color: zt.textPrimary),
              actions: [
                IconButton(
                  icon: const Icon(Icons.receipt_long),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ZiroActivityScreen(svc: _svc, merchant: widget.merchant)),
                  ),
                ),
              ],
            ),
      body: SafeArea(child: customerFacing ? _customer(context) : _amountView(context)),
    );
  }

  Widget _amountView(BuildContext context) {
    final zt = ZendTheme.of(context);
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', _currency == 'USD' ? '.' : '', '0', '<'];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Text(_amountShown, style: TextStyle(color: zt.textPrimary, fontSize: 56, fontWeight: FontWeight.w700)),
          const Spacer(),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            childAspectRatio: 1.8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final k in keys)
                k.isEmpty
                    ? const SizedBox()
                    : TextButton(
                        onPressed: () => _key(k),
                        child: k == '<'
                            ? Icon(Icons.backspace_outlined, color: zt.textPrimary)
                            : Text(k, style: TextStyle(color: zt.textPrimary, fontSize: 28)),
                      ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: ZiroCopy.charge(_amountShown),
            onPressed: (double.tryParse(_amount) ?? 0) > 0 ? _charge_ : null,
          ),
        ],
      ),
    );
  }

  Widget _customer(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    final amount = _charge?.amountLabel ?? _amountShown;
    Widget middle;
    switch (_step) {
      case _Step.starting:
      case _Step.checking:
      case _Step.settling:
        middle = Column(mainAxisSize: MainAxisSize.min, children: [
          const ZendLoader(),
          const SizedBox(height: 16),
          Text(_step == _Step.settling ? 'Paying…' : ZiroCopy.checking, style: white.copyWith(fontSize: 20)),
        ]);
      case _Step.palm:
        middle = Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: 280,
              height: 360,
              child: ZiroPreview(
                vision: _svc.vision,
                onError: (e) => _fail(ziroCameraErrorCopy(e.code)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(_guide, style: white.copyWith(fontSize: 22, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(ZiroCopy.handsLength, style: white.copyWith(color: Colors.white70)),
        ]);
      case _Step.pin:
        final d = _pinAsk?.display;
        middle = Column(mainAxisSize: MainAxisSize.min, children: [
          if (d != null) ...[
            CircleAvatar(
              radius: 32,
              backgroundImage: d.avatarUrl != null ? NetworkImage(d.avatarUrl!) : null,
              child: d.avatarUrl == null ? Text(d.firstName.characters.first) : null,
            ),
            const SizedBox(height: 10),
            Text(ZiroCopy.hi(d.firstName), style: white.copyWith(fontSize: 22, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Text(ZiroCopy.enterPin(amount, widget.merchant.businessName), style: white, textAlign: TextAlign.center),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_message, style: white.copyWith(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 16),
          ZiroPinPad(key: _pinKey, onComplete: _pin, dark: true),
        ]);
      case _Step.paid:
        final s = _settled!;
        middle = Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 72),
          const SizedBox(height: 12),
          Text(ZiroCopy.paid, style: white.copyWith(fontSize: 32, fontWeight: FontWeight.w700)),
          Text('${s.amountLabel} · ${widget.merchant.businessName}', style: white.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text(ZiroCopy.zirofee(s.feeLabel), style: white.copyWith(color: Colors.white60)),
          const SizedBox(height: 28),
          PrimaryButton(label: ZiroCopy.nextCustomer, onPressed: _reset),
        ]);
      case _Step.notFound:
        middle = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ZiroCopy.notFound, style: white.copyWith(fontSize: 24, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          PrimaryButton(label: ZiroCopy.tryAgain, onPressed: _charge_),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              _cancel();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ask them to pay with their Zend QR code.')),
              );
            },
            child: const Text(ZiroCopy.payAnotherWay, style: white),
          ),
        ]);
      case _Step.failed:
        middle = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_message.isEmpty ? ZiroCopy.failed : _message, style: white.copyWith(fontSize: 20), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          PrimaryButton(label: ZiroCopy.tryAgain, onPressed: _reset),
        ]);
      default:
        middle = const SizedBox();
    }
    final cancellable = _step != _Step.paid && _step != _Step.settling;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Text(widget.merchant.businessName, style: white.copyWith(color: Colors.white70)),
        Text(amount, style: white.copyWith(fontSize: 36, fontWeight: FontWeight.w700)),
        Expanded(child: Center(child: SingleChildScrollView(child: middle))),
        if (cancellable)
          TextButton(
            onPressed: _cancel,
            child: Text(_step == _Step.pin && _pinAsk?.display != null ? ZiroCopy.notYou : 'Cancel', style: white),
          ),
      ]),
    );
  }
}
