import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../activity/activity_grouping.dart';
import '../profile/user_profile_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// People — the identity/relationship gateway tab (ZEND BETA spec §17).
///
/// "Not a contact list. The gateway to relationships." Order per spec:
/// search, then Recent (people the viewer has actually transacted with —
/// this is what §1.5 means by Mutuals surfacing contextually rather than
/// owning a standalone section; there is no separate "Mutuals" backend
/// list distinct from transaction history, so Recent *is* that surface),
/// then a secondary/lightweight "People you might know" discovery row
/// sourced from the existing second-degree-connections endpoint.
///
/// Discovery stays strictly secondary (spec §69): capped at 5, no infinite
/// scroll, no engagement bait — just the one row the backend already
/// computes (`GET /api/zend/social/suggested-connections`).
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = ZendScope.of(context);
      if (model.suggestedConnections.isEmpty) model.fetchSuggestedConnections();
      // Recent's "N activities together" counts need the same data source
      // Feed already uses — no separate fetch, just make sure it's warm.
      if (model.threadedActivityEdges.isEmpty) model.fetchThreadedActivity();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Counterparty threads grouped off the build path.
  ///
  /// [groupByCounterparty] builds two maps over every edge, folds a sum and
  /// reduces a max per group, parses amounts and sorts the result. Running
  /// that inside build() meant paying for it on every notifyListeners() from
  /// the app model — including while this tab was swiped away, since the
  /// shell keeps all four tabs mounted. didChangeDependencies fires once per
  /// notify, which is the actual invalidation point.
  List<CounterpartyThread> _threads = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final model = ZendScope.of(context);
    _threads = groupByCounterparty(
      model.threadedActivityEdges,
      countIsExact: !model.threadedActivityHasMore,
    ).where((t) => !t.counterparty.isPool).toList();
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
    // Grouped in didChangeDependencies — see the field's doc.
    final threads = _threads;

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
                style: TextStyle(fontFamily: 'Geist', fontSize: 26, fontWeight: FontWeight.w700, color: zt.textPrimary),
              ),
            ),
            // ── Search — blends in, doesn't dominate ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                height: 44,
                decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.pill)),
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
              child: isSearching ? _buildSearchResults(zt) : _buildDefault(zt, model, threads),
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

  Widget _buildDefault(ZendTheme zt, ZendAppModel model, List<CounterpartyThread> threads) {
    if (threads.isEmpty) {
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

    final suggestions = model.suggestedConnections.take(5).toList();

    // Lazy, not eager. This was a `ListView(children: [...])` with an
    // uncapped `for (final thread in threads)` spread into it, so every
    // person the user has ever transacted with was constructed on every
    // rebuild whether or not they were anywhere near the viewport.
    //
    // Slot layout: [0] = "Recent" header, [1..n] = person rows,
    // [n+1] = the whole discovery section (capped at 5, so one widget).
    final hasSuggestions = suggestions.isNotEmpty;
    final itemCount = 1 + threads.length + (hasSuggestions ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: itemCount,
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
        if (i <= threads.length) {
          final thread = threads[i - 1];
          return _PersonRow(
            displayName: thread.counterparty.displayLabel,
            subtitle: '${thread.edges.length}${thread.countIsExact ? '' : '+'} '
                'activit${thread.edges.length == 1 ? 'y' : 'ies'} together',
            avatarUrl: thread.counterparty.avatarUrl,
            avatarLabel: thread.counterparty.initialLetter,
            onTap: () => _openProfile(
              zendtag: thread.counterparty.zendtag,
              userId: thread.counterparty.id,
              displayName: thread.counterparty.displayLabel,
              avatarUrl: thread.counterparty.avatarUrl,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'People you might know',
                style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
              ),
            ),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, j) {
                  final s = suggestions[j];
                  final tag = s['zendtag'] as String? ?? '';
                  final name = (s['display_name'] as String?)?.trim().isNotEmpty == true
                      ? s['display_name'] as String
                      : tag;
                  final avatarUrl = s['avatar_url'] as String?;
                  return _DiscoveryColumn(
                    displayName: name,
                    avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
                    avatarUrl: avatarUrl,
                    onTap: () => _openProfile(zendtag: tag, displayName: name, avatarUrl: avatarUrl),
                  );
                },
              ),
            ),
          ],
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

/// A single avatar + name column in the horizontal "People you might know"
/// strip — deliberately plain (no mutual-count badge, no follow button) so
/// it reads as a quiet, secondary row rather than a recommendation feed.
class _DiscoveryColumn extends StatelessWidget {
  const _DiscoveryColumn({
    required this.displayName,
    required this.avatarLabel,
    required this.onTap,
    this.avatarUrl,
  });

  final String displayName;
  final String avatarLabel;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            ZendAvatar(radius: 26, initials: avatarLabel, photoUrl: avatarUrl),
            const SizedBox(height: 6),
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Geist', fontSize: 11.5, color: zt.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
