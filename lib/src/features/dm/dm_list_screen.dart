import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/zend_selector.dart';
import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../../models/dm_thread.dart';
import '../../models/notification_category.dart';
import '../../navigation/zend_routes.dart';
import '../../services/e2ee_service.dart' show kE2eePrefix;
import '../../services/wallet_session_cache.dart';
import '../pools/pool.dart';
import '../pools/pool_detail_screen.dart';
import 'dm_thread_screen.dart';
import 'new_chat_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class DmListScreen extends StatefulWidget {
  const DmListScreen({super.key});

  @override
  State<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends State<DmListScreen> {
  List<DmThread> _threads = [];
  bool _loading = true;
  bool _loadError = false;
  String _searchQuery = '';
  bool _notificationsMuted = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ── Derived list state, computed off the build path ─────────────────────
  //
  // Merging DMs with pools, sorting the result, and then search-filtering it
  // used to happen inside build(). Every rebuild therefore allocated a
  // wrapper per row, sorted, and lowercased three strings per row — and this
  // widget rebuilds on every notifyListeners() from the app model, not just
  // when the chat list actually changes.
  //
  // Inputs are [_threads] (local), model.pools / model.poolsWithNewMessages
  // (model), and [_searchQuery] (local), so this is refreshed from both
  // didChangeDependencies and the setState paths that touch those.
  List<_ChatListItem> _items = const [];
  List<_ChatListItem> _displayItems = const [];

  // Inputs as of the last merge, so a no-op notify can skip it entirely —
  // see [_rebuildItems].
  List<Pool>? _lastSourcePools;
  List<DmThread>? _lastSourceThreads;
  Set<String>? _lastUnreadPoolIds;

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _loadMutePreference();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fires on every model notify, because build() takes a ZendScope
    // dependency. Reads with `read` since the dependency already exists.
    _rebuildItems();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.toLowerCase().trim();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
      _applySearch();
    });
  }

  /// One unified, sorted list — DMs and Pools mixed together with identical
  /// row styling, the way WhatsApp mixes groups and 1:1 chats in a single
  /// list rather than splitting them into separate sections.
  ///
  /// Pool has no last-activity timestamp on the client today (only
  /// created_at), so createdAt is the best available recency proxy for sort
  /// position until the backend exposes a real one. That only affects where
  /// an inactive pool lands in the list, never its row appearance.
  void _rebuildItems() {
    final model = ZendScope.read(context);
    final pools = model.pools;
    final unreadPools = model.poolsWithNewMessages;

    // Skip the merge+sort when none of its three inputs changed. Without this
    // it ran on every notifyListeners(), allocating a wrapper per row and
    // re-sorting, to produce a list identical to the one already on screen.
    //
    // `_threads` and `model.pools` are always *replaced* rather than mutated,
    // so identity is a sound signal for them. `poolsWithNewMessages` is a Set
    // that IS mutated in place (`.add(poolId)` on an incoming FCM message), so
    // identity says nothing about it and its contents have to be compared —
    // cheap, since it only holds pools with unread messages right now.
    final poolsUnchanged = identical(pools, _lastSourcePools);
    final threadsUnchanged = identical(_threads, _lastSourceThreads);
    final unreadUnchanged = _lastUnreadPoolIds != null &&
        _lastUnreadPoolIds!.length == unreadPools.length &&
        _lastUnreadPoolIds!.containsAll(unreadPools);
    if (poolsUnchanged && threadsUnchanged && unreadUnchanged) return;

    _lastSourcePools = pools;
    _lastSourceThreads = _threads;
    _lastUnreadPoolIds = Set<String>.of(unreadPools);

    _items = <_ChatListItem>[
      ..._threads.map(_ChatListItem.fromThread),
      ...pools.map((p) => _ChatListItem.fromPool(
            p,
            hasNewMessage: unreadPools.contains(p.id),
          )),
    ]..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    _applySearch();
  }

  void _applySearch() {
    _displayItems = _searchQuery.isEmpty
        ? _items
        : _items.where((item) => item.matches(_searchQuery)).toList();
  }

  Future<void> _loadMutePreference() async {
    final service = ZendScope.read(context).notificationPreferencesService;
    await service.load();
    if (mounted) {
      setState(() => _notificationsMuted = service.isMuted(NotificationCategoryKind.chat));
    }
  }

  Future<void> _toggleMute() async {
    final newValue = !_notificationsMuted;
    // Optimistic — the local preference write + backend sync happen in the
    // background; setMuted() never throws (backend failures are swallowed
    // internally), so there's nothing to roll back here.
    setState(() => _notificationsMuted = newValue);
    final model = ZendScope.read(context);
    await model.notificationPreferencesService.setMuted(
      NotificationCategoryKind.chat,
      newValue,
    );
  }

  Future<void> _loadThreads() async {
    setState(() {
      _loading = _threads.isEmpty;
      _loadError = false;
    });
    final model = ZendScope.of(context);
    if (model.pools.isEmpty && !model.poolsLoading) unawaited(model.fetchPools());
    try {
      final threads = await model.dmService.listThreads();
      if (mounted) {
        setState(() {
          _threads = threads;
          _loading = false;
          _loadError = false;
          _rebuildItems();
        });
        final total = threads.fold<int>(0, (sum, t) => sum + t.unreadCount);
        if (model.dmUnreadTotal != total) {
          model.setDmUnreadTotal(total);
        }
      }
      // Decrypt any E2EE thread previews in the background rather than
      // awaiting them here — the list is already fully usable with the
      // safe "🔒 New message" placeholder (see DmThread.lastMessagePreview),
      // so there's no reason to make the whole screen wait on a slow
      // network fetching counterparty keys. Each row silently upgrades to
      // the real preview text the moment its own decrypt resolves.
      unawaited(_decryptPreviews(model, threads));
    } catch (_) {
      // Only show the error state when there's nothing cached to fall back
      // on — a pull-to-refresh failure with existing threads on screen
      // should just silently keep showing the stale list rather than
      // replacing it with an error, but a *first* load failure previously
      // looked identical to "you have no chats", which is misleading.
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _threads.isEmpty;
        });
      }
    }
  }

  /// Threads beyond this index are extremely unlikely to be on-screen at
  /// first paint on any device — this is generously above what even a
  /// tablet in landscape shows above the fold. Decrypting them gets no
  /// visible-latency benefit, so they're deferred to the throttled tail
  /// batches below instead of firing alongside the priority batch.
  static const _kPriorityBatchSize = 20;

  /// Cap on concurrent decrypt operations for threads outside the priority
  /// batch. Each operation is a pubkey fetch (network, unless cached) plus
  /// local ECDH/HKDF/ChaCha20 work — fine to fire a handful at once, but with
  /// hundreds of threads (say, a heavy pool/community user) firing all of
  /// them simultaneously would mean hundreds of parallel HTTP requests to
  /// the pubkey endpoint on first login before any cache is warm.
  static const _kTailBatchSize = 8;

  /// Decrypts the last-message preview for every E2EE thread, updating the
  /// list as each one resolves.
  ///
  /// Threads are processed in two tiers to bound how much concurrent
  /// network/crypto work a single list load can trigger:
  ///   1. The first [_kPriorityBatchSize] threads (the ones actually visible
  ///      without scrolling, since the list is already sorted by recency)
  ///      decrypt together immediately — this is the case that matters for
  ///      perceived speed, so it gets no throttling.
  ///   2. Everything else decrypts in [_kTailBatchSize]-sized chunks, one
  ///      chunk at a time, so a huge thread list can't fan out into hundreds
  ///      of simultaneous pubkey requests on a cold cache.
  ///
  /// Deliberately never surfaces failures to the user — a counterparty
  /// without a registered key, a wallet that's locked, or a flaky network
  /// all just leave that row showing the generic "🔒 New message" fallback,
  /// which reads as normal chat-app behavior rather than an error. The
  /// underlying pubkey/room-key caches in [E2eeService] mean repeat calls
  /// (pull-to-refresh, returning from a thread) are network-free after the
  /// first successful resolution per counterparty.
  Future<void> _decryptPreviews(ZendAppModel model, List<DmThread> threads) async {
    final keypair = WalletSessionCache.instance.keypair;
    if (keypair == null) return; // wallet locked — retried on the next load
    final seed = keypair.length >= 32 ? keypair.sublist(0, 32) : keypair;
    try {
      final priority = threads.take(_kPriorityBatchSize);
      await Future.wait(
        priority.map((thread) => _decryptThreadPreview(model, thread, seed)),
      );

      final tail = threads.skip(_kPriorityBatchSize).toList();
      for (var i = 0; i < tail.length; i += _kTailBatchSize) {
        if (!mounted) return; // screen left — no point continuing in the background
        final chunk = tail.skip(i).take(_kTailBatchSize);
        await Future.wait(
          chunk.map((thread) => _decryptThreadPreview(model, thread, seed)),
        );
      }
    } finally {
      for (var i = 0; i < keypair.length; i++) {
        keypair[i] = 0;
      }
    }
  }

  Future<void> _decryptThreadPreview(
    ZendAppModel model,
    DmThread thread,
    Uint8List mySeed32,
  ) async {
    final lastMsg = thread.lastMessage;
    if (lastMsg == null || lastMsg.type != DmMessageType.text) return;
    final content = lastMsg.content;
    if (content == null || !content.startsWith(kE2eePrefix)) return;

    try {
      final pubkey = await model.e2eeService.fetchCounterpartyPubkey(
        thread.counterparty.userId,
      );
      if (pubkey == null) return; // no key on file — leave the fallback text
      final decrypted = await model.e2eeService.decrypt(
        wireContent: content,
        mySeed32: mySeed32,
        counterpartyPubkeyB58: pubkey,
        roomId: thread.roomId,
      );
      if (decrypted == null) return; // decryption failed — leave the fallback text
      lastMsg.content = decrypted;
      lastMsg.isEncrypted = true;
      // _ChatListItem holds the thread by reference, so the row picks the new
      // preview up without rebuilding the merged list. The search filter
      // reads through to it though, so re-apply that in case a query is
      // active and this row now matches (or stops matching).
      if (mounted) setState(_applySearch);
    } catch (_) {
      // Never let a decrypt failure bubble up — the model-level fallback
      // already covers display safety.
    }
  }

  void _openThread(DmThread thread) {
    pushZendSlide(
      context,
      DmThreadScreen(roomId: thread.roomId, counterparty: thread.counterparty),
    ).then((_) => _loadThreads());
  }

  void _openPool(Pool pool) {
    pushZendSlide(context, PoolDetailScreen(pool: pool)).then((_) => _loadThreads());
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    // Merged, sorted and filtered off the build path — see the fields' doc.
    final displayItems = _displayItems;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  // Notification mute toggle
                  IconButton(
                    onPressed: _toggleMute,
                    icon: Icon(
                      _notificationsMuted
                          ? PhosphorIconsRegular.bellSlash
                          : PhosphorIconsRegular.bell,
                      color: _notificationsMuted ? zt.accent : zt.textSecondary,
                      size: 24,
                    ),
                    tooltip: _notificationsMuted ? 'Unmute chat notifications' : 'Mute chat notifications',
                  ),
                ],
              ),
            ),

            // ── Persistent search pill ──
            // Always visible, WhatsApp-style, rather than hidden behind an
            // icon toggle — an always-present search invites use and gives
            // the header something to anchor visually against, instead of
            // costing the user an extra tap to even find it.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary.withValues(alpha: 0.7)),
                  prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 18, color: zt.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () => _searchController.clear(),
                          child: Icon(PhosphorIconsRegular.xCircle, size: 18, color: zt.textSecondary),
                        )
                      : null,
                  filled: true,
                  fillColor: zt.bgSecondary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // ── Unified chat list ──
            Expanded(
              child: _loading
                  ? const DmListSkeleton()
                  : _loadError
                      ? ZendErrorState(
                          title: "Couldn't load your chats",
                          onRetry: _loadThreads,
                        )
                      : displayItems.isEmpty
                          ? _searchQuery.isNotEmpty
                              ? Center(
                                  child: Text(
                                    'No chats matching "$_searchQuery"',
                                    style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                                  ),
                                )
                              : const _EmptyState()
                          : RefreshIndicator(
                              onRefresh: () => Future.wait([_loadThreads(), model.fetchPools()]),
                              // Selected on the merged list's identity, which
                              // [_rebuildItems] now keeps stable across notifies
                              // that don't touch chats — so a balance refresh
                              // or an activity event no longer rebuilds every
                              // visible chat row.
                              child: ZendSelector<List<_ChatListItem>>(
                                selector: (_) => _displayItems,
                                builder: (context, items, _) => ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: items.length,
                                itemBuilder: (context, i) {
                                  final item = items[i];
                                  // Boundaried per row: preview decryption
                                  // resolves one thread at a time and each
                                  // resolution setStates this screen, so
                                  // without this every arriving preview
                                  // repaints the whole visible list rather
                                  // than its own row.
                                  return RepaintBoundary(
                                    child: item.thread != null
                                        ? _DmThreadTile(
                                            key: ValueKey('dm-${item.thread!.roomId}'),
                                            thread: item.thread!,
                                            onTap: () => _openThread(item.thread!),
                                          )
                                        : _PoolThreadTile(
                                            key: ValueKey('pool-${item.pool!.id}'),
                                            pool: item.pool!,
                                            hasNewMessage: item.hasNewMessage,
                                            onTap: () => _openPool(item.pool!),
                                          ),
                                  );
                                },
                              ),
                              ),
                            ),
            ),
          ],
        ),
      ),
      // New chat/pool — spec §31-32, plus the request that this feel like
      // Zend's own action pattern (visually matching the Zend FAB) rather
      // than a plain header icon. Search/select from contacts to start a
      // DM, or create a pool — both from one entry point.
      floatingActionButton: _NewChatFab(onTap: () => showNewChatSheet(context)),
    );
  }
}

/// Wraps either a [DmThread] or a [Pool] so both can live in one sorted,
/// mixed list — exactly one of [thread]/[pool] is non-null.
class _ChatListItem {
  const _ChatListItem._({this.thread, this.pool, this.hasNewMessage = false});

  factory _ChatListItem.fromThread(DmThread t) => _ChatListItem._(thread: t);

  factory _ChatListItem.fromPool(Pool p, {required bool hasNewMessage}) =>
      _ChatListItem._(pool: p, hasNewMessage: hasNewMessage);

  final DmThread? thread;
  final Pool? pool;
  final bool hasNewMessage;

  DateTime get sortTime => thread?.lastMessageAt ?? pool!.createdAt;

  bool matches(String query) {
    if (thread != null) {
      final t = thread!;
      return t.counterparty.displayName.toLowerCase().contains(query) ||
          t.counterparty.zendtag.toLowerCase().contains(query) ||
          t.lastMessagePreview.toLowerCase().contains(query);
    }
    return pool!.name.toLowerCase().contains(query);
  }
}

/// Floating action for starting a new conversation or pool — visually
/// identical to the Zend FAB (`zend_shell.dart`'s `_ZendFab`: same deep
/// surface, size, and shadow) so the two primary floating actions in the
/// app read as one consistent pattern, just with a different glyph.
class _NewChatFab extends StatelessWidget {
  const _NewChatFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: ZendColors.bgDeep,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: const Center(
          child: Icon(PhosphorIconsRegular.plus, color: ZendColors.accentPop, size: 26),
        ),
      ),
    );
  }
}

class _DmThreadTile extends StatelessWidget {
  const _DmThreadTile({super.key, required this.thread, required this.onTap});
  final DmThread thread;
  final VoidCallback onTap;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final cp = thread.counterparty;
    final hasUnread = thread.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              // Avatar with presence badge
              Builder(builder: (ctx) {
                final dmService = ZendScope.of(ctx).dmService;
                final isOnline = dmService.presenceCache[cp.userId];
                return ZendAvatar(
                  radius: 26,
                  photoUrl: cp.avatarUrl,
                  initials: cp.initialLetter,
                  isOnline: isOnline,
                );
              }),
              const SizedBox(width: 14),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cp.displayName.trim().isEmpty ? '@${cp.zendtag}' : cp.displayName,
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 16,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                              color: zt.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(thread.lastMessageAt),
                          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 12, color: hasUnread ? zt.accent : zt.textSecondary.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.lastMessagePreview.isEmpty
                                ? 'Start a conversation'
                                : thread.lastMessagePreview,
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 14,
                              color: hasUnread ? zt.textPrimary : zt.textSecondary,
                              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            // Without this, a single-digit count (e.g. "1")
                            // doesn't naturally fill the 20px minWidth, and
                            // with no alignment set the digit sits off-center
                            // inside the wider forced box — looked like
                            // uneven/wrong padding around the number.
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: zt.accent,
                              borderRadius: BorderRadius.circular(ZendRadii.pill),
                            ),
                            child: Text(
                              thread.unreadCount > 99 ? '99+' : '${thread.unreadCount}',
                              style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
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

/// A Pool rendered as a group-conversation row — spec §25 ("Pools may
/// appear as group conversations"). Same row shape as [_DmThreadTile] so
/// it reads as "another conversation," not a separate financial-app
/// section bolted onto the chat list.
class _PoolThreadTile extends StatelessWidget {
  const _PoolThreadTile({
    super.key,
    required this.pool,
    required this.hasNewMessage,
    required this.onTap,
  });

  final Pool pool;
  final bool hasNewMessage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final subtitle = pool.targetAmount > 0
        ? '${pool.formattedGathered} of ${pool.formattedTarget}'
        : pool.formattedGathered;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(PhosphorIconsRegular.usersThree, size: 22, color: zt.textSecondary),
                  ),
                  if (hasNewMessage)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: ZendColors.destructive,
                          shape: BoxShape.circle,
                          border: Border.all(color: zt.bgPrimary, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: hasNewMessage ? FontWeight.w700 : FontWeight.w600, color: zt.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 13, color: zt.textSecondary),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.chatCircleText, size: 48, color: zt.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No chats yet',
            style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w600, color: zt.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Send a payment or tap a profile to start',
            style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
