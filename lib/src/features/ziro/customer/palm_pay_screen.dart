/// Palm pay for customers (R4, R7, R10): set up, limits, PIN, pause, delete and
/// payments with "Wasn't me". Opened from Settings → Palm pay.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ziro_vision/ziro_vision.dart';

import '../../../core/zend_format.dart' show formatMoney;
import '../../../core/zend_state.dart';
import '../../../design/zend_primitives.dart';
import '../../../design/zend_tokens.dart';
import '../../../services/sui_transaction_verifier.dart';
import '../shared/ziro_bytes.dart';
import '../shared/ziro_copy.dart';
import '../shared/ziro_models.dart';
import '../shared/ziro_pin_pad.dart';
import '../shared/ziro_pin_rules.dart';
import '../shared/ziro_service.dart';

/// Bump when counsel changes the consent text.
const kZiroConsentVersion = 'draft-2026-11';

class PalmPayScreen extends StatefulWidget {
  const PalmPayScreen({super.key});

  @override
  State<PalmPayScreen> createState() => _PalmPayScreenState();
}

class _PalmPayScreenState extends State<PalmPayScreen> {
  ZiroService? _svc;
  ZiroConfig? _config;
  ZiroCustomerStatus? _status;
  List<ZiroCustomerPayment> _payments = const [];
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_svc == null) {
      _svc = ZiroService(ZendScope.of(context));
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final c = await _svc!.config(refresh: true);
      ZiroCustomerStatus? s;
      var p = const <ZiroCustomerPayment>[];
      if (c.enabled) {
        s = await _svc!.api.me();
        if (s.isSetUp) p = await _svc!.api.myPayments();
      }
      if (mounted) setState(() {
        _config = c;
        _status = s;
        _payments = p;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ziroErrorText(e));
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ziroErrorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ZendAppModel get _model => ZendScope.of(context);

  Future<void> _pause(bool paused) => _run(() async {
        if (!paused) await _model.zkLoginService.satisfyStepUp();
        final (_, tx) = await _svc!.api.setPaused(paused);
        if (tx != null) {
          final e = await _svc!.expectation();
          await _svc!.signAndSubmit(tx, 'pause', (b) => verifyZiroPause(b, expectation: e, paused: paused));
        }
      });

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Turn off palm pay?'),
        content: const Text('Your palm details are destroyed and no shop can charge you with your palm. You can set it up again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final tx = await _svc!.api.deletePrepare();
      final e = await _svc!.expectation();
      await _svc!.signAndSubmit(tx, 'delete', (b) => verifyZiroDelete(b, expectation: e));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Palm pay is off and your palm details are gone.')));
    });
  }

  Future<void> _wasntMe(ZiroCustomerPayment p) => _run(() async {
        final tx = await _svc!.api.dispute(p.id);
        if (tx != null) {
          final e = await _svc!.expectation();
          await _svc!.signAndSubmit(tx, 'dispute', (b) => verifyZiroPause(b, expectation: e, paused: true));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Palm pay is paused. We'll look into this payment and get back to you.")),
          );
        }
      });

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final s = _status;
    final c = _config;
    Widget body;
    if (_error != null) {
      body = ZendErrorState(title: _error!, subtitle: '', onRetry: _load);
    } else if (c == null) {
      body = const Center(child: ZendLoader());
    } else if (!c.enabled) {
      body = const ZendErrorState(title: "Palm pay isn't available yet", subtitle: 'Check back soon.');
    } else if (s == null || !s.isSetUp) {
      body = ListView(padding: const EdgeInsets.all(24), children: [
        Text('Pay with your palm', style: TextStyle(color: zt.textPrimary, fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'At shops with Ziro, hold up your palm to pay from your Zend. No phone needed. '
          'You choose the limits and when your PIN is asked.',
          style: TextStyle(color: zt.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 32),
        PrimaryButton(label: 'Set up palm pay', onPressed: () => _open(PalmPayEnrollScreen(svc: _svc!))),
      ]);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
            title: Text(s.isOn ? 'Palm pay is on' : 'Palm pay is paused'),
            subtitle: Text(s.isOn ? 'Shops with Ziro can take payments with your palm.' : ZiroCopy.paused),
          ),
          ListTile(
            title: const Text('Limits'),
            subtitle: Text('No PIN up to ${s.noPinMaxLabel} · ${s.perPaymentMaxLabel} a payment · ${s.dailyMaxLabel} a day'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _open(PalmPayLimitsScreen(svc: _svc!, status: s, config: c)),
          ),
          ListTile(
            title: const Text('Change Ziro PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _open(PalmPayPinChangeScreen(svc: _svc!)),
          ),
          SwitchListTile(
            title: const Text('Palm pay'),
            value: s.isOn,
            onChanged: _busy ? null : (on) => _pause(!on),
          ),
          ListTile(
            title: Text('Turn off and delete', style: TextStyle(color: zt.destructive)),
            onTap: _busy ? null : _delete,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Palm payments', style: TextStyle(color: zt.textSecondary)),
          ),
          for (final p in _payments)
            ListTile(
              title: Text('${p.amountLabel} at ${p.merchant}'),
              subtitle: Text('${p.createdAt?.toLocal().toString().substring(0, 16) ?? ''}${p.pinUsed ? ' · PIN used' : ''}'),
              trailing: p.disputed
                  ? const Text('Being checked')
                  : TextButton(onPressed: _busy ? null : () => _wasntMe(p), child: const Text("Wasn't me")),
            ),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(
        backgroundColor: zt.bgPrimary,
        elevation: 0,
        title: Text('Palm pay', style: TextStyle(color: zt.textPrimary)),
        iconTheme: IconThemeData(color: zt.textPrimary),
      ),
      body: SafeArea(child: body),
    );
  }
}

// ===================== capture =====================

/// Guides the customer through both palms with the camera, returning the template.
class PalmCaptureView extends StatefulWidget {
  const PalmCaptureView({super.key, required this.svc, required this.face, required this.onCaptured});
  final ZiroService svc;
  final bool face;
  final ValueChanged<CapturedEvent> onCaptured;

  @override
  State<PalmCaptureView> createState() => _PalmCaptureViewState();
}

class _PalmCaptureViewState extends State<PalmCaptureView> {
  StreamSubscription<ZiroVisionEvent>? _sub;
  String _guide = 'Show your left palm';
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.svc.vision.prepare();
      _sub = widget.svc.vision.events.listen((e) {
        switch (e) {
          case GuideEvent(:final rawCode):
            setState(() => _guide = ziroGuideCopy(rawCode));
          case HandDoneEvent(:final hand):
            setState(() => _guide = hand == Hand.left ? 'Now show your right palm' : 'Got it');
          case CapturedEvent():
            widget.onCaptured(e);
          case ErrorEvent(:final rawCode):
            setState(() => _error = ziroCameraErrorCopy(rawCode));
          default:
            break;
        }
      });
      await widget.svc.vision.startCapture(mode: CaptureMode.enroll, face: widget.face, timeout: const Duration(seconds: 60));
    } catch (e) {
      if (mounted) setState(() => _error = ziroErrorText(e));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.svc.vision.stopCapture().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ZiroPreview(vision: widget.svc.vision, onError: (e) => setState(() => _error = ziroCameraErrorCopy(e.code))),
        ),
      ),
      const SizedBox(height: 16),
      Text(_error ?? _guide, style: TextStyle(color: _error != null ? zt.destructive : zt.textPrimary, fontSize: 20), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(ZiroCopy.handsLength, style: TextStyle(color: zt.textSecondary)),
    ]);
  }
}

// ===================== enrollment =====================

enum _E { consent, capture, pin, confirmPin, limits, saving }

class PalmPayEnrollScreen extends StatefulWidget {
  const PalmPayEnrollScreen({super.key, required this.svc});
  final ZiroService svc;

  @override
  State<PalmPayEnrollScreen> createState() => _PalmPayEnrollScreenState();
}

class _PalmPayEnrollScreenState extends State<PalmPayEnrollScreen> {
  _E _step = _E.consent;
  bool _agree = false;
  bool _face = false;
  ZiroEnrollStart? _start;
  CapturedEvent? _cap;
  String? _pin;
  String? _error;
  ZiroLimits? _limits;

  Future<void> _begin() async {
    setState(() => _error = null);
    try {
      await ZendScope.of(context).zkLoginService.satisfyStepUp();
      final s = await widget.svc.api.enrollStart(consentVersion: kZiroConsentVersion, faceOptIn: _face);
      final cfg = await widget.svc.config();
      setState(() {
        _start = s;
        _limits = cfg.defaults;
        _step = _E.capture;
      });
    } catch (e) {
      setState(() => _error = ziroErrorText(e));
    }
  }

  void _firstPin(String pin) {
    final problem = ziroPinProblem(pin);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _pin = pin;
      _error = null;
      _step = _E.confirmPin;
    });
  }

  void _secondPin(String pin) {
    if (pin != _pin) {
      setState(() {
        _pin = null;
        _error = "Those PINs didn't match. Start again.";
        _step = _E.pin;
      });
      return;
    }
    setState(() {
      _error = null;
      _step = _E.limits;
    });
  }

  Future<void> _save() async {
    final cap = _cap!, start = _start!, limits = _limits!;
    setState(() {
      _step = _E.saving;
      _error = null;
    });
    try {
      final receipt = await widget.svc.sendRecord(start, {
        'model_version': cap.modelVersion,
        'palms': [for (final p in cap.palms) p.toJson()],
        'geometry': cap.geometry,
        'face': cap.face,
        'pin': _pin,
      });
      _pin = null;
      final tx = await widget.svc.api.enrollPrepare(receipt: receipt, limits: limits);
      final e = await widget.svc.expectation();
      await widget.svc.signAndSubmit(
        tx,
        'enroll',
        (b) => verifyZiroEnroll(
          b,
          expectation: e,
          perPaymentMax: limits.perPaymentMax,
          noPinMax: limits.noPinMax,
          dailyMax: limits.dailyMax,
          commitment: zUnhex(receipt.commitmentHex),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Palm pay is on')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() {
        _error = ziroErrorText(e);
        _step = _E.limits;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    Widget body;
    switch (_step) {
      case _E.consent:
        body = ListView(children: [
          Text('Before you start', style: TextStyle(color: zt.textPrimary, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // DRAFT for counsel review (R13.3). Replace with approved text and bump kZiroConsentVersion.
          Text(
            '• We read the lines of both palms with your camera and turn them into numbers. Photos never leave your phone.\n'
            '• Those numbers are locked so only Zend\'s secure matching system can read them, and kept until you turn palm pay off.\n'
            '• Turning palm pay off destroys them for good.\n'
            '• You set the limits. Shops can never take more than you allow.\n'
            '• You can also add your face to make matching more accurate. This is optional.',
            style: TextStyle(color: zt.textPrimary, fontSize: 15, height: 1.5),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I agree to Zend reading my palms for palm pay'),
            value: _agree,
            onChanged: (v) => setState(() => _agree = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also use my face (optional)'),
            value: _face,
            onChanged: (v) => setState(() => _face = v),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: zt.destructive)),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Confirm it\'s you and continue', onPressed: _agree ? _begin : null),
        ]);
      case _E.capture:
        body = PalmCaptureView(
          svc: widget.svc,
          face: _face,
          onCaptured: (c) => setState(() {
            _cap = c;
            _step = _E.pin;
          }),
        );
      case _E.pin:
      case _E.confirmPin:
        body = Column(children: [
          Text(_step == _E.pin ? 'Choose a 4-digit Ziro PIN' : 'Enter it again',
              style: TextStyle(color: zt.textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('This is only for palm pay. Don\'t use your Zend PIN.', style: TextStyle(color: zt.textSecondary)),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: zt.destructive))],
          const Spacer(),
          ZiroPinPad(key: ValueKey(_step), shuffle: false, onComplete: _step == _E.pin ? _firstPin : _secondPin),
        ]);
      case _E.limits:
      case _E.saving:
        body = _LimitsEditor(
          config: widget.svc,
          limits: _limits!,
          error: _error,
          busy: _step == _E.saving,
          onChanged: (l) => setState(() => _limits = l),
          onSave: _save,
          saveLabel: 'Turn on palm pay',
        );
    }
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(backgroundColor: zt.bgPrimary, elevation: 0, iconTheme: IconThemeData(color: zt.textPrimary)),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: body)),
    );
  }
}

// ===================== limits =====================

class _LimitsEditor extends StatelessWidget {
  const _LimitsEditor({
    required this.config,
    required this.limits,
    required this.onChanged,
    required this.onSave,
    required this.saveLabel,
    this.error,
    this.busy = false,
  });
  final ZiroService config;
  final ZiroLimits limits;
  final ValueChanged<ZiroLimits> onChanged;
  final VoidCallback onSave;
  final String saveLabel;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final ceiling = config.cachedConfig?.noPinCeiling ?? limits.perPaymentMax;
    double usd(BigInt b) => b.toDouble() / 1000000;
    BigInt base(double v) => BigInt.from((v * 100).round()) * BigInt.from(10000);
    Widget slider(String label, BigInt value, double max, ValueChanged<double> set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ${formatMoney(usd(value))}', style: TextStyle(color: zt.textPrimary)),
            Slider(value: usd(value).clamp(0, max), max: max, divisions: (max * 4).round().clamp(1, 400), onChanged: busy ? null : set),
          ],
        );
    final perMax = usd(limits.dailyMax);
    return ListView(children: [
      Text('Your limits', style: TextStyle(color: zt.textPrimary, fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Shops can never take more than these.', style: TextStyle(color: zt.textSecondary)),
      const SizedBox(height: 16),
      slider('Pay without PIN up to', limits.noPinMax, usd(ceiling < limits.perPaymentMax ? ceiling : limits.perPaymentMax),
          (v) => onChanged(limits.copyWith(noPinMax: base(v)))),
      slider('Most for one payment', limits.perPaymentMax, perMax, (v) {
        final p = base(v);
        onChanged(limits.copyWith(perPaymentMax: p, noPinMax: limits.noPinMax > p ? p : limits.noPinMax));
      }),
      slider('Most in a day', limits.dailyMax, (usd(config.cachedConfig?.defaults.dailyMax ?? limits.dailyMax) * 4).clamp(1, 10000), (v) {
        final d = base(v);
        final p = limits.perPaymentMax > d ? d : limits.perPaymentMax;
        onChanged(limits.copyWith(dailyMax: d, perPaymentMax: p, noPinMax: limits.noPinMax > p ? p : limits.noPinMax));
      }),
      if (error != null) Text(error!, style: TextStyle(color: zt.destructive)),
      const SizedBox(height: 16),
      PrimaryButton(label: saveLabel, isLoading: busy, onPressed: busy ? null : onSave),
    ]);
  }
}

class PalmPayLimitsScreen extends StatefulWidget {
  const PalmPayLimitsScreen({super.key, required this.svc, required this.status, required this.config});
  final ZiroService svc;
  final ZiroCustomerStatus status;
  final ZiroConfig config;

  @override
  State<PalmPayLimitsScreen> createState() => _PalmPayLimitsScreenState();
}

class _PalmPayLimitsScreenState extends State<PalmPayLimitsScreen> {
  late ZiroLimits _limits = widget.status.limits;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tx = await widget.svc.api.limitsPrepare(_limits);
      final e = await widget.svc.expectation();
      await widget.svc.signAndSubmit(
        tx,
        'limits',
        (b) => verifyZiroLimits(
          b,
          expectation: e,
          perPaymentMax: _limits.perPaymentMax,
          noPinMax: _limits.noPinMax,
          dailyMax: _limits.dailyMax,
          currentDailyMax: widget.status.limits.dailyMax,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = ziroErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(backgroundColor: zt.bgPrimary, elevation: 0, iconTheme: IconThemeData(color: zt.textPrimary)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _LimitsEditor(
            config: widget.svc,
            limits: _limits,
            error: _error,
            busy: _busy,
            onChanged: (l) => setState(() => _limits = l),
            onSave: _save,
            saveLabel: 'Save limits',
          ),
        ),
      ),
    );
  }
}

// ===================== PIN change =====================

class PalmPayPinChangeScreen extends StatefulWidget {
  const PalmPayPinChangeScreen({super.key, required this.svc});
  final ZiroService svc;

  @override
  State<PalmPayPinChangeScreen> createState() => _PalmPayPinChangeScreenState();
}

class _PalmPayPinChangeScreenState extends State<PalmPayPinChangeScreen> {
  String? _first;
  String? _error;
  bool _busy = false;

  Future<void> _entered(String pin) async {
    if (_first == null) {
      final p = ziroPinProblem(pin);
      setState(() {
        _error = p;
        if (p == null) _first = pin;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = "Those PINs didn't match. Start again.";
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await ZendScope.of(context).zkLoginService.satisfyStepUp();
      final start = await widget.svc.api.pinStart();
      final receipt = await widget.svc.sendRecord(start, {'model_version': 'unchanged', 'pin': pin}, update: true);
      final tx = await widget.svc.api.commitmentPrepare(receipt);
      final e = await widget.svc.expectation();
      await widget.svc.signAndSubmit(tx, 'commitment', (b) => verifyZiroCommitment(b, expectation: e, commitment: zUnhex(receipt.commitmentHex)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your Ziro PIN is changed')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() {
        _error = ziroErrorText(e);
        _first = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(backgroundColor: zt.bgPrimary, elevation: 0, iconTheme: IconThemeData(color: zt.textPrimary)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_first == null ? 'New Ziro PIN' : 'Enter it again',
                style: TextStyle(color: zt.textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
            if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: zt.destructive))],
            const Spacer(),
            if (_busy) const ZendLoader() else ZiroPinPad(key: ValueKey(_first == null), shuffle: false, onComplete: _entered),
          ]),
        ),
      ),
    );
  }
}
