import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_thread.dart';
import '../../models/notification_category.dart';
import '../../navigation/zend_routes.dart';
import 'dm_thread_screen.dart';
import 'package:solar_icons/solar_icons.dart';

class DmListScreen extends StatefulWidget {
  const DmListScreen({super.key});

  @override
  State<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends State<DmListScreen> {
  List<DmThread> _threads = [];
  bool _loading = true;
  bool _searchActive = false;
  String _searchQuery = '';
  bool _notificationsMuted = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _loadMutePreference();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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
    setState(() => _loading = _threads.isEmpty);
    try {
      final model = ZendScope.of(context);
      final threads = await model.dmService.listThreads();
      if (mounted) {
        setState(() {
          _threads = threads;
          _loading = false;
        });
        final total = threads.fold<int>(0, (sum, t) => sum + t.unreadCount);
        if (model.dmUnreadTotal != total) {
          model.setDmUnreadTotal(total);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openThread(DmThread thread) {
    pushZendSlide(
      context,
      DmThreadScreen(roomId: thread.roomId, counterparty: thread.counterparty),
    ).then((_) => _loadThreads());
  }

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchController.clear();
        _searchFocus.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final displayThreads = _searchQuery.isEmpty
        ? _threads
        : _threads.where((t) {
            final name = t.counterparty.displayName.toLowerCase();
            final tag = t.counterparty.zendtag.toLowerCase();
            final preview = t.lastMessagePreview.toLowerCase();
            return name.contains(_searchQuery) ||
                tag.contains(_searchQuery) ||
                preview.contains(_searchQuery);
          }).toList();

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
                        fontFamily: 'Satoshi',
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
                          ? SolarIconsBold.bellOff
                          : SolarIconsBold.bell,
                      color: _notificationsMuted ? zt.accent : zt.textSecondary,
                      size: 24,
                    ),
                    tooltip: _notificationsMuted ? 'Unmute chat notifications' : 'Mute chat notifications',
                  ),
                  // Search toggle
                  IconButton(
                    onPressed: _toggleSearch,
                    icon: Icon(
                      _searchActive
                          ? SolarIconsBold.magnifierZoomOut
                          : SolarIconsBold.magnifier,
                      color: _searchActive ? zt.accent : zt.textSecondary,
                      size: 24,
                    ),
                    tooltip: _searchActive ? 'Close search' : 'Search chats',
                  ),
                ],
              ),
            ),

            // ── Inline search bar ──
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _searchActive
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: zt.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search chats…',
                          hintStyle: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: zt.textSecondary),
                          prefixIcon: Icon(SolarIconsBold.magnifier, size: 18, color: zt.textSecondary),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () => _searchController.clear(),
                                  child: Icon(SolarIconsBold.closeCircle, size: 18, color: zt.textSecondary),
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
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Thread list ──
            Expanded(
              child: _loading
                  ? const DmListSkeleton()
                  : displayThreads.isEmpty
                      ? _searchQuery.isNotEmpty
                          ? Center(
                              child: Text(
                                'No chats matching "$_searchQuery"',
                                style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: zt.textSecondary),
                              ),
                            )
                          : const _EmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadThreads,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: displayThreads.length,
                            itemBuilder: (_, i) => _DmThreadTile(
                              thread: displayThreads[i],
                              onTap: () => _openThread(displayThreads[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DmThreadTile extends StatelessWidget {
  const _DmThreadTile({required this.thread, required this.onTap});
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
                              fontFamily: 'Satoshi',
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
                              fontFamily: 'Satoshi',
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(SolarIconsBold.chatLine, size: 48, color: zt.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No chats yet',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w600, color: zt.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Send a payment or tap a profile to start',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13, color: zt.textSecondary.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
