import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_thread.dart';

/// Zend's own friend picker for ZApps (AppKit `zend.people.pick`). It lists
/// the user's chats; the app only ever learns about the people chosen here.
/// Returns the chosen counterparts, or an empty list if the user backs out.
Future<List<DmCounterparty>> showZAppPeoplePicker(
  BuildContext context, {
  required String appName,
  String? title,
  int max = 1,
}) async {
  final picked = await showZendModalSheet<List<DmCounterparty>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _Picker(appName: appName, title: title, max: max),
  );
  return picked ?? const [];
}

class _Picker extends StatefulWidget {
  const _Picker({required this.appName, this.title, required this.max});
  final String appName;
  final String? title;
  final int max;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  List<DmCounterparty>? _people;
  String? _error;
  String _query = '';
  final Map<String, DmCounterparty> _chosen = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final threads = await ZendScope.read(context).dmService.listThreads();
      final seen = <String>{};
      final people = <DmCounterparty>[
        for (final t in threads)
          if (seen.add(t.counterparty.userId)) t.counterparty,
      ];
      if (mounted) setState(() => _people = people);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load your chats");
    }
  }

  void _toggle(DmCounterparty p) {
    setState(() {
      if (_chosen.containsKey(p.userId)) {
        _chosen.remove(p.userId);
      } else if (widget.max == 1) {
        _chosen
          ..clear()
          ..[p.userId] = p;
      } else if (_chosen.length < widget.max) {
        _chosen[p.userId] = p;
      }
    });
  }

  String _label(DmCounterparty p) => p.displayName.trim().isNotEmpty
      ? p.displayName
      : (p.zendtag.contains('@')
            ? p.zendtag.split('@').first
            : '@${p.zendtag}');

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    final q = _query.toLowerCase();
    final people = (_people ?? const <DmCounterparty>[])
        .where(
          (p) =>
              q.isEmpty ||
              p.displayName.toLowerCase().contains(q) ||
              p.zendtag.toLowerCase().contains(q),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title ??
                    (widget.max == 1 ? 'Choose someone' : 'Choose people'),
                style: s(20, w: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.appName} only sees the people you pick.',
                style: s(13, c: zt.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(
                    PhosphorIconsRegular.magnifyingGlass,
                    color: zt.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: s(14, c: zt.textSecondary))
              else if (_people == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _people!.isEmpty
                        ? 'Start a chat with someone first, then you can pick them here.'
                        : 'No one matches that.',
                    style: s(14, c: zt.textSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in people)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () => _toggle(p),
                          leading: CircleAvatar(
                            backgroundColor: zt.bgSecondary,
                            backgroundImage: p.avatarUrl != null
                                ? NetworkImage(p.avatarUrl!)
                                : null,
                            child: p.avatarUrl == null
                                ? Text(
                                    _label(p).characters.first.toUpperCase(),
                                    style: s(15, w: FontWeight.w600),
                                  )
                                : null,
                          ),
                          title: Text(
                            _label(p),
                            style: s(15, w: FontWeight.w600),
                          ),
                          trailing: Icon(
                            _chosen.containsKey(p.userId)
                                ? PhosphorIconsFill.checkCircle
                                : PhosphorIconsRegular.circle,
                            color: _chosen.containsKey(p.userId)
                                ? zt.accent
                                : zt.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _chosen.isEmpty
                    ? 'Choose'
                    : widget.max == 1
                    ? 'Choose ${_label(_chosen.values.first)}'
                    : 'Choose ${_chosen.length}',
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_chosen.values.toList()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
