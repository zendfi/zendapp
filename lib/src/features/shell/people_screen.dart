import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/recent_contact.dart';
import '../../navigation/zend_routes.dart';
import '../profile/user_profile_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// People — the identity/relationship gateway tab (ZEND BETA spec §17).
///
/// "Not a contact list. The gateway to relationships." Structure per spec:
/// search first, then Recent (people the user has actually transacted
/// with), then a secondary/lightweight discovery row. No Mutuals section
/// yet — the backend doesn't expose a mutual-connections list to the
/// client today (only server-side `mutual_connections` used for activity
/// visibility authorization), so that section is deferred until that data
/// is surfaced rather than faked with placeholder content.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';

  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _searchResults = [];
    });
    _debounce?.cancel();
    if (_query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(_query));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final model = ZendScope.of(context);
      final results = await model.walletService.apiClient.searchUsers(q);
      if (mounted && _query == q) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openProfile({String? zendtag, String? userId, String? displayName, String? avatarUrl}) {
    pushZendSlide(
      context,
      UserProfileScreen(
        zendtag: zendtag,
        userId: userId,
        knownDisplayName: displayName,
        knownAvatarUrl: avatarUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final isSearching = _query.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'People',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
            ),
            // ── Search — blends in, doesn't dominate ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: zt.bgSecondary,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
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
    if (_searching && _searchResults.isEmpty) {
      return const SearchUsersSkeleton();
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          "We couldn't find anyone with that identity.",
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _searchResults.length,
      itemBuilder: (context, i) {
        final u = _searchResults[i];
        final tag = u['zendtag'] as String? ?? '';
        final name = u['display_name'] as String? ?? tag;
        final avatarUrl = u['avatar_url'] as String?;
        return _PersonRow(
          displayName: name,
          subtitle: '@$tag',
          avatarUrl: avatarUrl,
          avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
          onTap: () => _openProfile(zendtag: tag, displayName: name, avatarUrl: avatarUrl),
        );
      },
    );
  }

  Widget _buildDefault(ZendTheme zt, List<RecentContact> recent) {
    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Nothing here yet. Zend someone to get things started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: recent.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              'Recent',
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
            ),
          );
        }
        final c = recent[i - 1];
        return _PersonRow(
          displayName: c.name.isNotEmpty ? c.name : c.tag,
          subtitle: '@${c.tag}',
          avatarUrl: c.avatarUrl,
          avatarLabel: c.avatarLabel,
          onTap: () => _openProfile(zendtag: c.tag, displayName: c.name, avatarUrl: c.avatarUrl),
        );
      },
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
  final VoidCallback onTap;

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
                    Text(
                      displayName,
                      style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                    ),
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
