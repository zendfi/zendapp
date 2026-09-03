import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../../models/recent_contact.dart';
import '../pools/create_pool_drawer.dart';
import 'dm_thread_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// New Chat/Pool entry point — reached from the Chats tab's floating
/// action button. Search/select a contact or mutual to start a DM, or
/// create a pool via the button that sits just above that list.
///
/// This is where pool creation lives now (moved off the Chats header,
/// per the request that Chats itself carry no DM/Pool differentiator) —
/// grouped here with starting a 1:1 chat since both are "start a new
/// conversation" actions from the user's point of view.
Future<void> showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.92,
      child: NewChatSheet(),
    ),
  );
}

class NewChatSheet extends StatefulWidget {
  const NewChatSheet({super.key});

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _results = [];
    });
    _debounce?.cancel();
    if (_query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(_query));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final model = ZendScope.of(context);
      final results = await model.walletService.apiClient.searchUsers(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _startChat({required String userId, required String displayName}) async {
    final model = ZendScope.of(context);
    try {
      final result = await model.dmService.getOrCreateRoom(userId);
      if (!mounted) return;
      Navigator.of(context).pop();
      pushZendSlide(context, DmThreadScreen(roomId: result.roomId, counterparty: result.counterparty));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start that chat — try again", style: TextStyle(fontFamily: 'Geist'))),
        );
      }
    }
  }

  /// [RecentContact] and search results only carry a zendtag, not a
  /// userId — `getUserProfile` (not `zendtagService.resolve`, whose
  /// response has no userId field at all) is the lightest existing call
  /// that returns one, so it's used here purely to get the id the DM room
  /// endpoint requires.
  Future<void> _startChatByTag(String tag) async {
    final model = ZendScope.of(context);
    try {
      final profile = await model.walletService.apiClient.getUserProfile(tag);
      if (!mounted) return;
      await _startChat(userId: profile.userId, displayName: profile.displayName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start that chat — try again", style: TextStyle(fontFamily: 'Geist'))),
        );
      }
    }
  }

  void _createPool() {
    Navigator.of(context).pop();
    showCreatePoolDrawer(context, targetAmount: 0);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final isSearching = _query.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Center(child: ZendSheetHandle()),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'New chat',
                style: TextStyle(fontFamily: 'Geist', fontSize: 20, fontWeight: FontWeight.w700, color: zt.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 44,
                decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: _onQueryChanged,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search username or email',
                    hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                    prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: zt.textSecondary),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(PhosphorIconsRegular.xCircle, size: 18, color: zt.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: isSearching ? _buildSearchResults(zt) : _buildDefault(zt, model.recentContacts),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ZendTheme zt) {
    if (_searching && _results.isEmpty) {
      return const SearchUsersSkeleton();
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          "We couldn't find anyone with that identity.",
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final u = _results[i];
        // Search results carry no user id (GET /api/zend/users/search only
        // returns zendtag/display_name/avatar_url) — resolve by tag, same
        // as the Recent-contact path below.
        final tag = u['zendtag'] as String? ?? '';
        final name = (u['display_name'] as String?)?.trim().isNotEmpty == true ? u['display_name'] as String : tag;
        return _PersonRow(
          displayName: name,
          subtitle: '@$tag',
          avatarUrl: u['avatar_url'] as String?,
          avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
          onTap: tag.isEmpty ? null : () => _startChatByTag(tag),
        );
      },
    );
  }

  Widget _buildDefault(ZendTheme zt, List<RecentContact> recent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // "Create pool" sits just before the contact list, per spec — a
        // pool starts the same way a chat does: pick people, then it
        // becomes its own conversation.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _createPool,
            borderRadius: BorderRadius.circular(ZendRadii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: zt.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(PhosphorIconsRegular.usersThree, size: 20, color: zt.accent),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Create pool',
                    style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: zt.border, height: 1),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Search for someone to start a chat.',
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Recent',
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
            ),
          ),
          for (final c in recent)
            _PersonRow(
              displayName: c.name.isNotEmpty ? c.name : c.tag,
              subtitle: '@${c.tag}',
              avatarUrl: c.avatarUrl,
              avatarLabel: c.avatarLabel,
              onTap: c.tag.isEmpty ? null : () => _startChatByTag(c.tag),
            ),
        ],
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.displayName,
    required this.subtitle,
    required this.avatarLabel,
    required this.onTap,
    this.avatarUrl,
  });

  final String displayName;
  final String subtitle;
  final String avatarLabel;
  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              ZendAvatar(radius: 20, initials: avatarLabel, photoUrl: avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary)),
                    Text(subtitle, style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
