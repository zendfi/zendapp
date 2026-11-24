import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../models/app_notification.dart';
import 'notification_opener.dart';

/// Everything Zend told the user about: money, links, messages, reactions.
/// On web this is the only place to catch up, since there is no push.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ZendScope.of(context).fetchNotifications());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      final model = ZendScope.of(context);
      if (model.notificationsHasMore && !model.notificationsLoading) {
        unawaited(model.fetchNotifications(more: true));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final items = model.notifications;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        PhosphorIconsRegular.caretLeft,
                        color: zt.textPrimary,
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.96,
                        fontSize: 24,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  if (model.notificationsUnread > 0)
                    TextButton(
                      onPressed: () =>
                          unawaited(model.markAllNotificationsRead()),
                      child: Text(
                        'Mark all as read',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 14,
                          color: zt.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: model.fetchNotifications,
                child: _body(context, zt, model, items),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ZendTheme zt,
    ZendAppModel model,
    List<AppNotification> items,
  ) {
    if (items.isEmpty) {
      final loading = model.notificationsLoading || !model.notificationsLoaded;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          if (loading)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  Icon(
                    PhosphorIconsRegular.bellSimple,
                    size: 40,
                    color: zt.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nothing new',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Money, messages and links show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final rows = <Widget>[];
    String? lastGroup;
    for (final n in items) {
      final group = _groupFor(n.createdAt);
      if (group != lastGroup) {
        rows.add(_GroupLabel(group));
        lastGroup = group;
      }
      rows.add(
        _NotificationTile(
          n: n,
          onTap: () => unawaited(openInboxItem(context, model, n)),
        ),
      );
    }
    if (model.notificationsHasMore) {
      rows.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: rows,
    );
  }

  static String _groupFor(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!t.isBefore(today)) return 'Today';
    if (!t.isBefore(today.subtract(const Duration(days: 6)))) {
      return 'This week';
    }
    return 'Older';
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});

  final AppNotification n;
  final VoidCallback onTap;

  IconData get _icon => switch (n.category) {
    'chat' => PhosphorIconsRegular.chatCircleText,
    'activity' => PhosphorIconsRegular.heart,
    'pools' => PhosphorIconsRegular.usersThree,
    'savings' => PhosphorIconsRegular.piggyBank,
    _ => PhosphorIconsRegular.arrowDownLeft,
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final unread = !n.read;
    // A chat that collapsed several messages says how many.
    final body = n.count > 1 && n.category == 'chat'
        ? '${n.count} new messages'
        : n.body;

    return Semantics(
      button: true,
      label: '${unread ? 'Unread. ' : ''}${n.title}. $body',
      excludeSemantics: true,
      child: Material(
        color: unread ? zt.bgCard : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: zt.bgSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 18, color: zt.textPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 15,
                          fontWeight: unread
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: zt.textPrimary,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 14,
                            color: zt.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _timeLabel(n.createdAt),
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          color: zt.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: zt.accentPop,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _timeLabel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day} ${months[t.month - 1]}';
  }
}
