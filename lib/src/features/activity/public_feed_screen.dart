import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import 'activity_grouping.dart';

/// Answers "where do users see public posts?" — a dedicated feed of every
/// Shared_Network Activity_Edge the viewer is authorized to see via a
/// mutual connection (i.e. `!isDirectParticipant` rows already included in
/// `ZendAppModel.threadedActivityEdges`, per Req 5.3's Shared_Network_Viewer
/// grant).
///
/// Public feed posts are deliberately READ-ONLY for the viewer: they are
/// neither a direct party to these activities, nor able to comment on them
/// (enforced server-side), and tapping to open a comment sheet would be
/// confusing since they can only observe. The tile is therefore non-tappable.
class PublicFeedScreen extends StatelessWidget {
  const PublicFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    final publicEdges = model.threadedActivityEdges.where((e) => !e.isDirectParticipant).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: zt.textPrimary),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Public',
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                        ),
                        Text(
                          "Activity your mutuals have shared",
                          style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: zt.border, height: 1),
            Expanded(
              child: publicEdges.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          "Nothing public yet. When one of your mutuals shares an activity with their network, it shows up here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: publicEdges.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final edge = publicEdges[i];
                        return _PublicPostRow(edge: edge);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicPostRow extends StatelessWidget {
  const _PublicPostRow({required this.edge});

  final ActivityEdge edge;

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
    final amountLabel = edge.amountHidden ? 'Hidden' : '\$${edge.amountUsdc ?? '0'}';

    // Always third-person: "@sender paid @recipient" — feedVerbFor returns
    // a third-person verb for direction=='external' edges (no "you" pronoun).
    final verb = feedVerbFor(edge);
    final senderTag = edge.senderZendtag;
    final recipientTag = edge.recipientZendtag;
    final senderLabel = senderTag != null && senderTag.isNotEmpty ? '@$senderTag' : 'Someone';
    final recipientLabel = recipientTag != null && recipientTag.isNotEmpty ? '@$recipientTag' : 'someone';
    final senderInitial = senderTag?.isNotEmpty == true ? senderTag![0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZendAvatar(radius: 18, photoUrl: edge.senderAvatarUrl, initials: senderInitial),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                    children: [
                      TextSpan(text: senderLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' $verb '),
                      TextSpan(text: recipientLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _relativeTime(edge.createdAt),
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.8)),
                ),
                if (edge.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    edge.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textPrimary.withValues(alpha: 0.85)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amountLabel,
            style: TextStyle(fontFamily: 'DMMono', fontSize: 13, fontWeight: FontWeight.w700, color: zt.textSecondary),
          ),
        ],
      ),
    );
  }
}
