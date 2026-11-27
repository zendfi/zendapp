import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_format.dart' show formatNaira;
import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../pairing/device_approval_sheet.dart';

/// Settings → Devices: boards that take payments or check people in for this person, grouped
/// (a laundry room, a fleet of kiosks), with takings, settings, commands, alerts and shares.
/// Staff see their groups read-only.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>>? _devices;
  List<Map<String, dynamic>> _groups = const [];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await ZendScope.read(context).walletService.apiClient.getMyDevices();
      if (!mounted) return;
      setState(() {
        _devices = (r['devices'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList();
        _groups = (r['groups'] as List? ?? const []).map((g) => Map<String, dynamic>.from(g as Map)).toList();
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      _say(done);
      await _load();
    } on ApiException catch (e) {
      _say(e.userMessage);
    } catch (_) {
      _say("That didn't go through. Try again.");
    }
  }

  Future<String?> _ask(String title, String initial, {TextInputType? type, String? hint, int lines = 1}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: type,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<String?> _pick(List<(String, IconData, String)> items) => showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (key, icon, label) in items)
                  ListTile(
                    leading: Icon(icon, color: key == 'remove' ? Colors.red : null),
                    title: Text(label, style: key == 'remove' ? const TextStyle(color: Colors.red) : null),
                    onTap: () => Navigator.pop(c, key),
                  ),
              ],
            ),
          ),
        ),
      );

  /// "@shop 20, @landlord 10" ↔ shares.
  String _sharesText(List? shares) =>
      (shares ?? const []).map((s) => '@${(s as Map)['handle']} ${s['percent']}').join(', ');
  List<Map<String, dynamic>>? _parseShares(String text) {
    final out = <Map<String, dynamic>>[];
    for (final part in text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty)) {
      final bits = part.split(RegExp(r'\s+'));
      final pct = bits.length == 2 ? double.tryParse(bits[1].replaceAll('%', '')) : null;
      if (pct == null) return null;
      out.add({'handle': bits[0].replaceAll('@', ''), 'percent': pct});
    }
    return out;
  }

  Future<void> _editShares(String title, List? current, Future<void> Function(List<Map<String, dynamic>>) save) async {
    final t = await _ask(title, _sharesText(current), hint: '@shopowner 20, @landlord 10');
    if (t == null) return;
    final shares = _parseShares(t);
    if (shares == null) return _say('Write it like: @shopowner 20, @landlord 10');
    await _run(() => save(shares), shares.isEmpty ? 'Not shared any more' : 'Shares saved. They apply to new payments.');
  }

  Future<void> _editConfig(String title, Map? current, Future<void> Function(Map<String, dynamic>) save) async {
    final t = await _ask(title, const JsonEncoder.withIndent('  ').convert(current ?? {}),
        hint: '{"price_ngn": 500, "minutes": 30}', lines: 6);
    if (t == null) return;
    try {
      final v = jsonDecode(t.isEmpty ? '{}' : t);
      if (v is! Map) throw const FormatException();
      await _run(() => save(Map<String, dynamic>.from(v)), 'Saved. The device picks it up within seconds.');
    } on FormatException {
      _say('Settings must look like {"price_ngn": 500}');
    }
  }

  Future<void> _deviceMenu(Map<String, dynamic> d) async {
    final api = ZendScope.read(context).walletService.apiClient;
    final id = d['id'] as String;
    if (d['role'] != 'owner') return _say('You can see this device, but only its owner can change it.');
    final paused = d['paused'] == true;
    final pick = await _pick([
      ('config', PhosphorIconsRegular.slidersHorizontal, 'Settings (price, times)'),
      ('command', PhosphorIconsRegular.paperPlaneTilt, 'Send a command'),
      ('history', PhosphorIconsRegular.clockCounterClockwise, 'Recent commands'),
      ('shares', PhosphorIconsRegular.chartPie, 'Share payments'),
      ('alert', PhosphorIconsRegular.bellRinging, 'Tell me when it goes offline'),
      ('group', PhosphorIconsRegular.folder, 'Move to a group'),
      ('limit', PhosphorIconsRegular.gauge, 'Largest amount it can ask for'),
      ('rename', PhosphorIconsRegular.pencilSimple, 'Rename'),
      ('pause', paused ? PhosphorIconsRegular.play : PhosphorIconsRegular.pause, paused ? 'Resume' : 'Pause'),
      ('remove', PhosphorIconsRegular.trash, 'Remove'),
    ]);
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'config':
        await _editConfig('Settings for ${d['name']}', d['config'] as Map?, (c) => api.setDeviceConfig(id, c));
      case 'command':
        final n = await _ask('Command', '', hint: 'open, restart, free_cycle');
        if (n != null && n.isNotEmpty) await _run(() => api.sendDeviceCommand(id, n), 'Sent');
      case 'history':
        final cmds = await api.getDeviceCommands(id);
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Recent commands'),
            content: Text(cmds.isEmpty
                ? 'None yet.'
                : cmds.map((x) => '${x['name']} · ${x['status']}${x['result'] != null ? ': ${x['result']}' : ''}').join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
          ),
        );
      case 'shares':
        await _editShares('Share each payment', d['shares'] as List?, (s) => api.setDeviceShares(id, s));
      case 'alert':
        final m = await _pick([
          ('5', PhosphorIconsRegular.timer, 'After 5 minutes'),
          ('30', PhosphorIconsRegular.timer, 'After 30 minutes'),
          ('60', PhosphorIconsRegular.timer, 'After 1 hour'),
          ('180', PhosphorIconsRegular.timer, 'After 3 hours'),
          ('0', PhosphorIconsRegular.bellSlash, "Don't tell me"),
        ]);
        if (m != null) await _run(() => api.updateDevice(id, offlineAlertMins: int.parse(m)), 'Saved');
      case 'group':
        final g = await _pick([
          for (final g in _groups.where((g) => g['role'] == 'owner')) (g['id'] as String, PhosphorIconsRegular.folder, g['name'] as String),
          ('none', PhosphorIconsRegular.x, 'No group'),
        ]);
        if (g != null) {
          await _run(() => g == 'none' ? api.updateDevice(id, ungroup: true) : api.updateDevice(id, groupId: g), 'Moved');
        }
      case 'limit':
        final v = await _ask('Largest amount, in Naira', (d['max_request_ngn'] as num).toStringAsFixed(0),
            type: TextInputType.number, hint: '20000');
        final n = double.tryParse(v?.replaceAll(',', '') ?? '');
        if (n != null) await _run(() => api.updateDevice(id, maxRequestNgn: n), 'Saved');
      case 'rename':
        final n = await _ask('Rename device', d['name'] as String);
        if (n != null && n.isNotEmpty) await _run(() => api.updateDevice(id, name: n), 'Renamed');
      case 'pause':
        await _run(() => api.updateDevice(id, paused: !paused), paused ? 'Resumed' : "Paused. It can't ask for payments until you resume it.");
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Remove ${d['name']}?'),
            content: const Text('It stops working at once. Payments already made stay in your Zend.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
            ],
          ),
        );
        if (ok == true) await _run(() => api.removeDevice(id), 'Removed');
    }
  }

  Future<void> _groupMenu(Map<String, dynamic> g) async {
    final api = ZendScope.read(context).walletService.apiClient;
    final id = g['id'] as String;
    if (g['role'] != 'owner') return _say("You're staff in this group: you see its devices and alerts.");
    final pick = await _pick([
      ('config', PhosphorIconsRegular.slidersHorizontal, 'Settings for every device'),
      ('shares', PhosphorIconsRegular.chartPie, 'Share payments from every device'),
      ('staff', PhosphorIconsRegular.userPlus, 'Add staff (they see, not change)'),
      ('unstaff', PhosphorIconsRegular.userMinus, 'Remove staff'),
      ('rename', PhosphorIconsRegular.pencilSimple, 'Rename'),
      ('remove', PhosphorIconsRegular.trash, 'Remove group (devices stay)'),
    ]);
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'config':
        await _editConfig('Settings for ${g['name']}', g['config'] as Map?, (c) => api.updateDeviceGroup(id, config: c));
      case 'shares':
        await _editShares('Share payments in ${g['name']}', g['shares'] as List?, (s) => api.setDeviceGroupShares(id, s));
      case 'staff':
        final h = await _ask('Add staff', '', hint: '@handle');
        if (h != null && h.isNotEmpty) await _run(() => api.addDeviceGroupStaff(id, h), 'Added');
      case 'unstaff':
        final h = await _ask('Remove staff', '', hint: '@handle');
        if (h != null && h.isNotEmpty) await _run(() => api.removeDeviceGroupStaff(id, h), 'Removed');
      case 'rename':
        final n = await _ask('Rename group', g['name'] as String);
        if (n != null && n.isNotEmpty) await _run(() => api.updateDeviceGroup(id, name: n), 'Renamed');
      case 'remove':
        await _run(() => api.removeDeviceGroup(id), 'Group removed. Its devices are still here.');
    }
  }

  Future<void> _add() async {
    final pick = await _pick([
      ('device', PhosphorIconsRegular.cpu, 'Add a device'),
      ('group', PhosphorIconsRegular.folderPlus, 'New group'),
    ]);
    if (!mounted || pick == null) return;
    if (pick == 'device') {
      final added = await showDeviceApprovalSheet(context);
      if (added == true) _load();
    } else {
      final n = await _ask('New group', '', hint: 'Hostel laundry room');
      if (n != null && n.isNotEmpty) {
        await _run(() => ZendScope.read(context).walletService.apiClient.createDeviceGroup(n), 'Group made');
      }
    }
  }

  Widget _deviceTile(ZendTheme zt, TextStyle Function(double, {FontWeight w, Color? c}) s, Map<String, dynamic> d) {
    final paused = d['paused'] == true;
    final seen = DateTime.tryParse(d['last_seen_at'] as String? ?? '');
    final online = seen != null && DateTime.now().difference(seen).inMinutes < 2;
    final shared = (d['shares'] as List? ?? const []).isNotEmpty;
    final app = d['run_by_app'] as String?;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _deviceMenu(d),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border.all(color: zt.border), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.cpu, color: zt.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['name'] as String, style: s(15, w: FontWeight.w600)),
                  Text(
                    [
                      paused ? 'Paused' : online ? 'Online' : 'Offline',
                      if (shared) 'Shared',
                      if (app != null) 'Run by $app',
                    ].join(' · '),
                    style: s(12, c: paused ? Colors.orange : online ? Colors.green : zt.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatNaira((d['today_ngn'] as num).toDouble()), style: s(15, w: FontWeight.w600)),
                Text('today · ${d['payments']} paid in all', style: s(12, c: zt.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontFamily: 'Geist', fontSize: size, fontWeight: w, color: c ?? zt.textPrimary, height: 1.35);
    final devices = _devices;
    final sections = <Widget>[];
    if (devices != null) {
      for (final g in _groups) {
        final inGroup = devices.where((d) => d['group_id'] == g['id']).toList();
        final today = inGroup.fold<double>(0, (a, d) => a + (d['today_ngn'] as num).toDouble());
        sections.add(InkWell(
          onTap: () => _groupMenu(g),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.folder, size: 18, color: zt.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${g['name']}${g['role'] == 'staff' ? ' · staff' : ''}',
                    style: s(14, w: FontWeight.w700),
                  ),
                ),
                Text('${formatNaira(today)} today', style: s(13, c: zt.textSecondary)),
              ],
            ),
          ),
        ));
        for (final d in inGroup) {
          sections.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _deviceTile(zt, s, d)));
        }
      }
      final loose = devices.where((d) => d['group_id'] == null || !_groups.any((g) => g['id'] == d['group_id'])).toList();
      if (loose.isNotEmpty && _groups.isNotEmpty) {
        sections.add(Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 8), child: Text('Not in a group', style: s(14, w: FontWeight.w700))));
      }
      for (final d in loose) {
        sections.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _deviceTile(zt, s, d)));
      }
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Devices', style: s(26, w: FontWeight.w700))),
                  TextButton.icon(onPressed: _add, icon: const Icon(PhosphorIconsRegular.plus, size: 18), label: const Text('Add')),
                ],
              ),
            ),
            Expanded(
              child: _failed
                  ? Center(child: Text("Couldn't load your devices", style: s(14, c: zt.textSecondary)))
                  : devices == null
                      ? const Center(child: CircularProgressIndicator())
                      : devices.isEmpty && _groups.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'Boards you build, like a laundry timer, a water point or a gym door, can ask people to pay you or check them in. Add one with the code on its screen.',
                                  textAlign: TextAlign.center,
                                  style: s(14, c: zt.textSecondary),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: sections),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
