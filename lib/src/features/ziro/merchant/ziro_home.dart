/// Ziro for merchants, opened as the built-in `ziro` ZApp (design §13). Loads the
/// merchant and this phone's registration, then shows onboarding, phone setup
/// or the till.
library;

import 'package:flutter/material.dart';

import '../../../core/zend_state.dart';
import '../../../design/zend_primitives.dart';
import '../../../design/zend_tokens.dart';
import '../shared/ziro_copy.dart';
import '../shared/ziro_models.dart';
import '../shared/ziro_service.dart';
import 'ziro_activity.dart';
import 'ziro_till.dart';

class ZiroHome extends StatefulWidget {
  const ZiroHome({super.key});

  @override
  State<ZiroHome> createState() => _ZiroHomeState();
}

class _ZiroHomeState extends State<ZiroHome> {
  ZiroService? _svc;
  ZiroConfig? _config;
  ZiroMerchant? _merchant;
  ZiroDeviceRecord? _device;
  String? _error;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_svc == null) {
      _svc = ZiroService(ZendScope.of(context));
      _load();
    }
  }

  Future<void> _load() async {
    final svc = _svc!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await svc.config(refresh: true);
      ZiroMerchant? m;
      ZiroDeviceRecord? d;
      if (c.enabled) {
        m = await svc.api.myMerchant();
        d = await svc.savedDevice();
        if (d != null && !d.fresh) d = null;
        // Warm the palm models while the merchant looks at the screen.
        if (m != null && m.active && d != null) svc.vision.prepare().ignore();
      }
      if (!mounted) return;
      setState(() {
        _config = c;
        _merchant = m;
        _device = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ziroErrorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    Widget body;
    if (_loading) {
      body = const Center(child: ZendLoader());
    } else if (_error != null) {
      body = ZendErrorState(title: _error!, subtitle: '', onRetry: _load);
    } else if (_config?.enabled != true) {
      body = const ZendErrorState(title: "Ziro isn't available yet", subtitle: 'Check back soon.');
    } else if (_merchant == null || !_merchant!.active) {
      body = _Onboarding(svc: _svc!, config: _config!, merchant: _merchant, onDone: _load);
    } else if (_device == null) {
      body = _PhoneSetup(svc: _svc!, onDone: _load);
    } else {
      return ZiroTill(svc: _svc!, merchant: _merchant!, device: _device!, config: _config!);
    }
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(
        backgroundColor: zt.bgPrimary,
        elevation: 0,
        title: Text('Ziro', style: TextStyle(color: zt.textPrimary)),
        iconTheme: IconThemeData(color: zt.textPrimary),
        actions: [
          if (_merchant?.active == true)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ZiroActivityScreen(svc: _svc!, merchant: _merchant!)),
              ),
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding({required this.svc, required this.config, required this.merchant, required this.onDone});
  final ZiroService svc;
  final ZiroConfig config;
  final ZiroMerchant? merchant;
  final VoidCallback onDone;

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _name = TextEditingController();
  String _category = 'Food and drink';
  List<ZiroCampus> _campuses = const [];
  String? _campus;
  bool _busy = false;
  String? _error;

  static const _categories = ['Food and drink', 'Shop', 'Books and print', 'Services', 'Transport', 'Other'];

  @override
  void initState() {
    super.initState();
    widget.svc.api.campuses().then((c) {
      if (mounted) setState(() => _campuses = c);
    }).ignore();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _campus == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.svc.api.registerMerchant(businessName: _name.text.trim(), category: _category, campusId: _campus!);
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = ziroErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final pending = widget.merchant != null && !widget.merchant!.active;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Sell with Ziro', style: TextStyle(color: zt.textPrimary, fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Customers pay with a palm scan. Money goes straight to your Zend.',
          style: TextStyle(color: zt.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text('Ziro fee ${widget.config.feePercent} per payment.', style: TextStyle(color: zt.textSecondary, fontSize: 15)),
        if (pending) ...[
          const SizedBox(height: 16),
          Text(
            widget.merchant!.status == 'suspended'
                ? 'Ziro is paused for your business. Contact Zend support.'
                : 'Ziro is still being set up. Try again in a moment.',
            style: TextStyle(color: zt.destructive),
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Business name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'What you sell'),
          items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _campus,
          decoration: const InputDecoration(labelText: 'Campus'),
          items: [for (final c in _campuses) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => _campus = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: zt.destructive)),
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Start selling',
          isLoading: _busy,
          onPressed: _name.text.trim().isEmpty || _campus == null || _busy ? null : _submit,
        ),
      ],
    );
  }
}

class _PhoneSetup extends StatefulWidget {
  const _PhoneSetup({required this.svc, required this.onDone});
  final ZiroService svc;
  final VoidCallback onDone;

  @override
  State<_PhoneSetup> createState() => _PhoneSetupState();
}

class _PhoneSetupState extends State<_PhoneSetup> {
  bool _busy = false;
  String? _error;

  Future<void> _setup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.svc.registerThisPhone();
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = ziroErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set up this phone', style: TextStyle(color: zt.textPrimary, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'This phone will take palm payments for your business. You can remove it any time.',
            style: TextStyle(color: zt.textSecondary, fontSize: 15),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: zt.destructive)),
          ],
          const Spacer(),
          PrimaryButton(label: 'Set up this phone', isLoading: _busy, onPressed: _busy ? null : _setup),
        ],
      ),
    );
  }
}
