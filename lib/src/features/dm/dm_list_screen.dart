import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_thread.dart';
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

  @override
  void initState() {
    super.initState();
    _loadThreads();
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
        // Sync unread total
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
      DmThreadScreen(
        roomId: thread.roomId,
        counterparty: thread.counterparty,
      ),
    ).then((_) => _loadThreads()); // refresh unread on return
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(SolarIconsBold.magnifier,
                        color: zt.textSecondary, size: 20),
                    onPressed: () {}, // search stub
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ZendLoader(size: 24))
                  : _threads.isEmpty
                      ? _EmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadThreads,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _threads.length,
                            itemBuilder: (_, i) => _DmThreadTile(
                              thread: _threads[i],
                              onTap: () => _openThread(_threads[i]),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              ZendAvatar(
                radius: 22,
                photoUrl: cp.avatarUrl,
                initials: cp.initialLetter,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cp.displayName.trim().isEmpty
                          ? '@${cp.zendtag}'
                          : cp.displayName,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.lastMessagePreview.isEmpty
                          ? 'Start a conversation'
                          : thread.lastMessagePreview,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        color: thread.unreadCount > 0
                            ? zt.textPrimary
                            : zt.textSecondary,
                        fontWeight: thread.unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _relativeTime(thread.lastMessageAt),
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: zt.textSecondary,
                    ),
                  ),
                  if (thread.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: zt.accentBright,
                        borderRadius:
                            BorderRadius.circular(ZendRadii.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${thread.unreadCount > 99 ? '99+' : thread.unreadCount}',
                        style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              shape: BoxShape.circle,
            ),
            child: Icon(SolarIconsBold.chatLine,
                size: 28, color: zt.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send a message from someone\'s profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
