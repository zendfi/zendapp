import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_thread.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Shows a bottom sheet listing the user's DM threads so they can pick who
/// to forward a message to. Returns the chosen [DmCounterparty] and
/// [roomId], or null if dismissed without a selection.
Future<({String roomId, DmCounterparty counterparty})?> showDmForwardSheet(
  BuildContext context,
) {
  return showModalBottomSheet<({String roomId, DmCounterparty counterparty})>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DmForwardSheet(),
  );
}

class _DmForwardSheet extends StatefulWidget {
  const _DmForwardSheet();

  @override
  State<_DmForwardSheet> createState() => _DmForwardSheetState();
}

class _DmForwardSheetState extends State<_DmForwardSheet> {
  List<DmThread> _threads = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = ZendScope.read(context);
    try {
      // Prefer the already-cached thread list (populated by DmListScreen)
      // to avoid a network round-trip most of the time — falls back to a
      // fresh fetch if the cache is empty (e.g. forwarding from a cold
      // deep-link straight into a thread).
      final cached = model.dmService.cachedThreads;
      final threads = cached.isNotEmpty ? cached : await model.dmService.listThreads();
      if (mounted) setState(() { _threads = threads; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final filtered = _query.isEmpty
        ? _threads
        : _threads.where((t) {
            final name = t.counterparty.displayName.toLowerCase();
            final tag = t.counterparty.zendtag.toLowerCase();
            return name.contains(_query) || tag.contains(_query);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            const ZendSheetHandle(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Forward to',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 20, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(PhosphorIconsBold.xCircle, color: zt.textSecondary, size: 24),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: zt.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: zt.textSecondary.withValues(alpha: 0.7)),
                  prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18, color: zt.textSecondary),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.pill), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: ZendLoader(size: 22))
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty ? 'No chats yet' : 'No chats matching "$_query"',
                            style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: zt.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final thread = filtered[i];
                            final cp = thread.counterparty;
                            return ListTile(
                              onTap: () => Navigator.of(context).pop((roomId: thread.roomId, counterparty: cp)),
                              leading: ZendAvatar(radius: 20, photoUrl: cp.avatarUrl, initials: cp.initialLetter),
                              title: Text(
                                cp.displayName.trim().isEmpty ? '@${cp.zendtag}' : cp.displayName,
                                style: TextStyle(fontFamily: 'Satoshi', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary),
                              ),
                              subtitle: Text(
                                '@${cp.zendtag}',
                                style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 12, color: zt.textSecondary),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
