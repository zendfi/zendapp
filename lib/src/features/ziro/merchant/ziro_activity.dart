/// Merchant activity (R11): today's total, payments with fee and net, refunds,
/// sound and haptics, and this business's phones.
library;

import 'package:flutter/material.dart';

import '../../../design/zend_primitives.dart';
import '../../../design/zend_tokens.dart';
import '../shared/ziro_copy.dart';
import '../shared/ziro_models.dart';
import '../shared/ziro_service.dart';

class ZiroActivityScreen extends StatefulWidget {
  const ZiroActivityScreen({super.key, required this.svc, required this.merchant});
  final ZiroService svc;
  final ZiroMerchant merchant;

  @override
  State<ZiroActivityScreen> createState() => _ZiroActivityScreenState();
}

class _ZiroActivityScreenState extends State<ZiroActivityScreen> {
  ZiroMerchantPayments? _data;
  List<ZiroDevice> _devices = const [];
  late ZiroMerchant _merchant = widget.merchant;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.svc.api.merchantPayments();
      final devices = await widget.svc.api.devices();
      if (mounted) setState(() {
        _data = d;
        _devices = devices;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ziroErrorText(e));
    }
  }

  Future<void> _refund(ZiroMerchantPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Refund this payment?'),
        content: Text('${p.amountLabel} goes back to ${p.customer} from your Zend.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Refund')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.svc.refund(p.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refunded')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ziroErrorText(e))));
    }
  }

  Future<void> _setting({bool? sound, bool? haptics}) async {
    try {
      final m = await widget.svc.api.updateMerchantSettings(sound: sound, haptics: haptics);
      if (mounted) setState(() => _merchant = m);
    } catch (_) {}
  }

  Future<void> _removeDevice(ZiroDevice d) async {
    try {
      await widget.svc.api.removeDevice(d.id);
      final mine = await widget.svc.savedDevice();
      if (mine?.deviceId == d.id) await widget.svc.forgetThisPhone();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ziroErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final d = _data;
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(
        backgroundColor: zt.bgPrimary,
        elevation: 0,
        title: Text('Payments', style: TextStyle(color: zt.textPrimary)),
        iconTheme: IconThemeData(color: zt.textPrimary),
      ),
      body: _error != null
          ? ZendErrorState(title: _error!, subtitle: '', onRetry: _load)
          : d == null
              ? const Center(child: ZendLoader())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Today', style: TextStyle(color: zt.textSecondary)),
                      Text(d.todayTotalLabel, style: TextStyle(color: zt.textPrimary, fontSize: 32, fontWeight: FontWeight.w700)),
                      Text('${d.todayCount} payments', style: TextStyle(color: zt.textSecondary)),
                      const SizedBox(height: 16),
                      for (final p in d.payments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${p.customer} · ${p.amountLabel}', style: TextStyle(color: zt.textPrimary)),
                          subtitle: Text(
                            'Ziro fee ${p.feeLabel} · you get ${p.netLabel}${p.refundedLabel != null ? ' · refunded ${p.refundedLabel}' : ''}',
                            style: TextStyle(color: zt.textSecondary),
                          ),
                          trailing: p.refundedLabel == null
                              ? TextButton(onPressed: () => _refund(p), child: const Text('Refund'))
                              : null,
                        ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sound'),
                        value: _merchant.sound,
                        onChanged: (v) => _setting(sound: v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vibrate'),
                        value: _merchant.haptics,
                        onChanged: (v) => _setting(haptics: v),
                      ),
                      const Divider(),
                      Text('Phones that take payments', style: TextStyle(color: zt.textSecondary)),
                      for (final dev in _devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(dev.platform == 'ios' ? 'iPhone' : 'Android phone'),
                          subtitle: Text('Added ${dev.createdAt?.toLocal().toString().split(' ').first ?? ''}'),
                          trailing: TextButton(onPressed: () => _removeDevice(dev), child: const Text('Remove')),
                        ),
                    ],
                  ),
                ),
    );
  }
}
