import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/dm_group.dart';
import '../../models/dm_thread.dart';
import '../../design/zend_verified_badge.dart';

/// Result of the info sheet, so the thread can react.
enum GroupInfoResult { left, changed }

/// Members, roles, rename, mute, add and leave for one group.
Future<GroupInfoResult?> showGroupInfoSheet(
  BuildContext context, {
  required String roomId,
  required String myUserId,
}) {
  return showModalBottomSheet<GroupInfoResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GroupInfoSheet(roomId: roomId, myUserId: myUserId),
  );
}

class _GroupInfoSheet extends StatefulWidget {
  const _GroupInfoSheet({required this.roomId, required this.myUserId});
  final String roomId;
  final String myUserId;

  @override
  State<_GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends State<_GroupInfoSheet> {
  DmGroupDetail? _g;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _run(Future<DmGroupDetail> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await action();
      if (!mounted) return;
      setState(() {
        _g = g;
        _busy = false;
        _changed = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _load() async {
    final dm = ZendScope.of(context).dmService;
    try {
      final g = await dm.getGroup(widget.roomId);
      if (mounted) setState(() => _g = g);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<String?> _askText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 40),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final g = _g!;
    final dm = ZendScope.of(context).dmService;
    final name = await _askText('Group name', g.name);
    if (name == null || name.isEmpty || name == g.name) return;
    await _run(() => dm.updateGroup(widget.roomId, name: name));
  }

  Future<void> _addPeople() async {
    final g = _g!;
    final dm = ZendScope.of(context).dmService;
    final threads = dm.cachedThreads.isNotEmpty
        ? dm.cachedThreads
        : await dm.listThreads();
    final inGroup = g.members.map((m) => m.userId).toSet();
    final candidates = threads
        .where(
          (t) =>
              !t.isGroup &&
              t.counterparty.userId.isNotEmpty &&
              !inGroup.contains(t.counterparty.userId),
        )
        .map((t) => t.counterparty)
        .toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPeoplePicker(
        candidates: candidates,
        room: g.maxMembers - g.members.length,
      ),
    );
    if (picked == null || picked.isEmpty) return;
    await _run(() => dm.addGroupMembers(widget.roomId, picked));
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text("You won't get new messages from it."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final dm = ZendScope.of(context).dmService;
    setState(() => _busy = true);
    try {
      await dm.removeGroupMember(widget.roomId, widget.myUserId);
      if (mounted) Navigator.pop(context, GroupInfoResult.left);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _memberActions(DmGroupMember m) async {
    final g = _g!;
    final dm = ZendScope.of(context).dmService;
    final canRemove =
        g.iAmOwner && !m.isOwner || (g.iAmAdmin && m.role == 'member');
    final canPromote = g.iAmOwner && !m.isOwner;
    if (!canRemove && !canPromote) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPromote)
              ListTile(
                title: Text(
                  m.role == 'admin' ? 'Remove as admin' : 'Make admin',
                ),
                onTap: () => Navigator.pop(ctx, 'admin'),
              ),
            if (canRemove)
              ListTile(
                title: const Text('Remove from group'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == 'admin') {
      await _run(
        () =>
            dm.setGroupAdmin(widget.roomId, m.userId, admin: m.role != 'admin'),
      );
    } else if (choice == 'remove') {
      try {
        setState(() => _busy = true);
        await dm.removeGroupMember(widget.roomId, m.userId);
        await _load();
        if (mounted) {
          setState(() {
            _busy = false;
            _changed = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = friendlyError(e);
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final g = _g;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pop(context, _changed ? GroupInfoResult.changed : null);
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: g == null
            ? SizedBox(
                height: 200,
                child: Center(
                  child: _error != null
                      ? Text(_error!)
                      : const CircularProgressIndicator(),
                ),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  Center(
                    child: ZendAvatar(
                      seed: 'group:${g.roomId}',
                      radius: 36,
                      initials: g.emoji ?? (g.name.isEmpty ? '?' : g.name[0]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      g.name,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${g.members.length} members',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        color: zt.textSecondary,
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: zt.destructive),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (g.iAmAdmin)
                    ListTile(
                      leading: const Icon(PhosphorIconsRegular.pencilSimple),
                      title: const Text('Rename group'),
                      onTap: _busy ? null : _rename,
                    ),
                  SwitchListTile(
                    secondary: const Icon(PhosphorIconsRegular.bellSlash),
                    title: const Text('Mute notifications'),
                    value: g.muted,
                    onChanged: _busy
                        ? null
                        : (v) => _run(
                            () => ZendScope.of(
                              context,
                            ).dmService.updateGroup(widget.roomId, muted: v),
                          ),
                  ),
                  if (g.iAmAdmin && !g.isFull)
                    ListTile(
                      leading: const Icon(PhosphorIconsRegular.userPlus),
                      title: const Text('Add people'),
                      onTap: _busy ? null : _addPeople,
                    ),
                  const Divider(),
                  for (final m in g.members)
                    ListTile(
                      onTap: m.userId == widget.myUserId
                          ? null
                          : () => _memberActions(m),
                      leading: ZendAvatar(
                        seed: m.userId,
                        radius: 18,
                        photoUrl: m.avatarUrl,
                        initials: m.initialLetter,
                      ),
                      title: PersonName(
                        m.userId == widget.myUserId
                            ? 'You'
                            : (m.displayName.trim().isEmpty
                                  ? '@${m.zendtag}'
                                  : m.displayName),
                        verified: m.humanVerified,
                      ),
                      subtitle: Text(
                        '@${m.zendtag}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: m.isAdmin
                          ? Text(
                              m.isOwner ? 'Owner' : 'Admin',
                              style: TextStyle(
                                fontSize: 12,
                                color: zt.textSecondary,
                              ),
                            )
                          : null,
                    ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      PhosphorIconsRegular.signOut,
                      color: zt.destructive,
                    ),
                    title: Text(
                      'Leave group',
                      style: TextStyle(color: zt.destructive),
                    ),
                    onTap: _busy ? null : _leave,
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddPeoplePicker extends StatefulWidget {
  const _AddPeoplePicker({required this.candidates, required this.room});
  final List<DmCounterparty> candidates;
  final int room;

  @override
  State<_AddPeoplePicker> createState() => _AddPeoplePickerState();
}

class _AddPeoplePickerState extends State<_AddPeoplePicker> {
  final _sel = <String>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Add people',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          Flexible(
            child: widget.candidates.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Everyone you chat with is already in.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in widget.candidates)
                        CheckboxListTile(
                          value: _sel.contains(c.userId),
                          onChanged: (v) => setState(() {
                            if (v == true && _sel.length < widget.room) {
                              _sel.add(c.userId);
                            } else {
                              _sel.remove(c.userId);
                            }
                          }),
                          secondary: ZendAvatar(
                            seed: c.userId,
                            radius: 18,
                            photoUrl: c.avatarUrl,
                            initials: c.initialLetter,
                          ),
                          title: PersonName(
                            c.displayName.trim().isEmpty
                                ? '@${c.zendtag}'
                                : c.displayName,
                            verified: c.humanVerified,
                          ),
                          subtitle: Text(
                            '@${c.zendtag}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sel.isEmpty
                    ? null
                    : () => Navigator.pop(context, _sel.toList()),
                child: const Text('Add'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
