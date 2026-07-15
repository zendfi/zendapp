import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import 'activity_comment_sheet.dart';
import 'activity_grouping.dart';
import 'activity_receipt_builder.dart';
import 'thread_detail_screen.dart';
import 'transaction_receipt_sheet.dart';

/// Answers "where do users see public posts?" — a dedicated feed of every
/// Shared_Network Activity_Edge the viewer is authorized to see via a
/// mutual connection (i.e. `!isDirectParticipant` rows already included in
/// `ZendAppModel.threadedActivityEdges`, per Req 5.3's Shared_Network_Viewer
/// grant). Direct-participant edges the viewer made public themselves are
/// intentionally excluded here — those already show in the viewer's own
/// threads; this feed is specifically "activity other people chose to
/// share with their network that I can see because we're mutuals."
class PublicFeedScreen extends StatelessWidget {
  const PublicFeedScreen({super.key});

  void _openReceipt(BuildContext context, ActivityEdge edge) {
    final model = ZendScope.of(context);
    final entry = entryFromEdgeForViewer(edge, model);
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details for this activity are not available', style: TextStyle(fontFamily: 'DMSans'))),
      );
      return;
    }
    final tx = zendTransactionFromEdge(edge, entry, avatarLabel: edge.counterparty.initialLetter, avatarUrl: edge.counterparty.avatarUrl);
    showTransactionReceipt(context, tx: tx);
  }

  /// Tapping a public post opens the comment sheet first (consistent with
  /// Thread_Detail's own tap-through) — neither party here is necessarily
  /// the viewer, so the headline reads as a third-party observation.
  void _openActivity(BuildContext context, ActivityEdge edge) {
    final verb = feedVerbFor(edge);
    final senderLabel = edge.senderZendtag != null ? '@${edge.senderZendtag}' : 'Someone';
    final recipientLabel = edge.recipientZendtag != null ? '@${edge.recipientZendtag}' : 'someone';
    showActivityCommentSheet(
      context,
      edge: edge,
      headline: '$senderLabel $verb $recipientLabel',
      avatarUrl: edge.senderAvatarUrl,
      avatarInitial: senderLabel.isNotEmpty && senderLabel != 'Someone' ? senderLabel[1].toUpperCase() : '?',
      onViewReceipt: () => _openReceipt(context, edge),
    );
  }

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
                        return _PublicPostRow(
                          edge: edge,
                          onTap: () => _openActivity(context, edge),
                          onOpenThread: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ThreadDetailScreen(counterparty: edge.counterparty, edges: [edge]),
                          )),
                        );
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
  const _PublicPostRow({required this.edge, required this.onTap, required this.onOpenThread});

  final ActivityEdge edge;
  final VoidCallback onTap;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amountLabel = edge.amountHidden ? 'Hidden' : '\$${edge.amountUsdc ?? '0'}';
    final verb = feedVerbFor(edge);

    // Neither party is necessarily the viewer here — describe as a
    // third-party observation: "@sender paid @recipient".
    final senderLabel = edge.senderZendtag != null ? '@${edge.senderZendtag}' : 'Someone';
    final recipientLabel = edge.recipientZendtag != null ? '@${edge.recipientZendtag}' : 'someone';

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: onTap,
        onLongPress: onOpenThread,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZendAvatar(radius: 18, photoUrl: edge.senderAvatarUrl, initials: senderLabel.isNotEmpty ? senderLabel[1].toUpperCase() : '?'),
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
                    if (edge.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        edge.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary),
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
        ),
      ),
    );
  }
}
