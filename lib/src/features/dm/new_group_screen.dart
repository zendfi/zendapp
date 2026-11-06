import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/dm_group.dart';
import '../../models/dm_thread.dart';
import '../../navigation/zend_routes.dart';
import 'dm_thread_screen.dart';

const int _kMaxGroupMembers = 20;

/// Pick people you already chat with, name the group, create it.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _selected = <String>{};
  List<DmCounterparty> _contacts = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dm = ZendScope.of(context).dmService;
    try {
      final threads = dm.cachedThreads.isNotEmpty
          ? dm.cachedThreads
          : await dm.listThreads();
      if (!mounted) return;
      setState(() {
        _contacts = threads
            .where((t) => !t.isGroup && t.counterparty.userId.isNotEmpty)
            .map((t) => t.counterparty)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  bool get _canCreate =>
      !_creating && _selected.length >= 2 && _nameCtrl.text.trim().isNotEmpty;

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    final dm = ZendScope.of(context).dmService;
    try {
      final DmGroupDetail g = await dm.createGroup(
        name: _nameCtrl.text.trim(),
        emoji: _emojiCtrl.text.trim().isEmpty ? null : _emojiCtrl.text.trim(),
        memberIds: _selected.toList(),
      );
      if (!mounted) return;
      final summary = DmGroupSummary(
        roomId: g.roomId,
        name: g.name,
        emoji: g.emoji,
        memberCount: g.members.length,
      );
      final nav = Navigator.of(context);
      nav.pop();
      pushZendSlide(
        nav.context,
        DmThreadScreen(
          roomId: g.roomId,
          counterparty: summary.asCounterparty(),
          group: summary,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(
        backgroundColor: zt.bgPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: zt.textPrimary),
        title: Text(
          'New group',
          style: TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w700,
            color: zt.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _emojiCtrl,
                    textAlign: TextAlign.center,
                    maxLength: 2,
                    style: const TextStyle(fontSize: 24),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '🙂',
                      filled: true,
                      fillColor: zt.bgSecondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.xl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    maxLength: 40,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontFamily: 'Geist',
                      color: zt.textPrimary,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Group name',
                      filled: true,
                      fillColor: zt.bgSecondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.xl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selected.length} of ${_kMaxGroupMembers - 1} picked · pick at least 2',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(child: _buildList(zt)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                _error!,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: zt.destructive,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _canCreate ? _create : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: zt.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZendRadii.pill),
                    ),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Create group',
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ZendTheme zt) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Chat with a few people first. You can add anyone you\'ve already messaged.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (_, i) {
        final c = _contacts[i];
        final on = _selected.contains(c.userId);
        return ListTile(
          onTap: () => setState(() {
            if (on) {
              _selected.remove(c.userId);
            } else if (_selected.length < _kMaxGroupMembers - 1) {
              _selected.add(c.userId);
            }
          }),
          leading: ZendAvatar(
            seed: c.userId,
            radius: 20,
            photoUrl: c.avatarUrl,
            initials: c.initialLetter,
          ),
          title: Text(
            c.displayName.trim().isEmpty ? '@${c.zendtag}' : c.displayName,
            style: TextStyle(
              fontFamily: 'Geist',
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          subtitle: Text(
            '@${c.zendtag}',
            style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary),
          ),
          trailing: Icon(
            on ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.circle,
            color: on ? zt.accent : zt.textSecondary,
          ),
        );
      },
    );
  }
}
