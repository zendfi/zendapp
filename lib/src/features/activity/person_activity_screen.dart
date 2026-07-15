import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import 'activity_comment_sheet.dart';
import 'activity_grouping.dart';
import 'activity_receipt_builder.dart';
import 'transaction_receipt_sheet.dart';

/// Opened by tapping a person node in the "Your Mutuals" Graph_View —
/// shows that person's full authorized activity: the viewer's own edges
/// with them, plus (when the viewer is a Shared_Network_Viewer of that
/// person) that person's own Shared_Network edges with other people too.
/// Backed by `GET /api/zend/activity/users/:user_id/edges`, which performs
/// this authorization entirely server-side (Req 19.2 — no separate/
/// duplicate authorization path).
class PersonActivityScreen extends StatefulWidget {
  const PersonActivityScreen({super.key, required this.userId, required this.label, this.avatarUrl});

  final String userId;
  final String label;
  final String? avatarUrl;

  @override
  State<PersonActivityScreen> createState() => _PersonActivityScreenState();
}

class _PersonActivityScreenState extends State<PersonActivityScreen> {
  List<ActivityEdge> _edges = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = ZendScope.of(context);
    try {
      final response = await model.activityDataService.getActivityEdgesForUser(widget.userId, limit: 50);
      if (mounted) setState(() => _edges = response.edges);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openReceipt(ActivityEdge edge) {
    final model = ZendScope.of(context);
    final entry = entryFromEdgeForViewer(edge, model);
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details for this activity are not available', style: TextStyle(fontFamily: 'DMSans'))),
      );
      return;
    }
    final tx = zendTransactionFromEdge(
      edge,
      entry,
      avatarLabel: edge.counterparty.initialLetter,
      avatarUrl: edge.counterparty.avatarUrl,
    );
    showTransactionReceipt(context, tx: tx);
  }

  /// Tapping an activity opens the comment sheet first — consistent with
  /// Thread_Detail's tap-through. The headline is whatever _describeEdge
  /// already produced for this row. For a direct viewer<->target edge, the
  /// "other side" avatar is always the target person (widget.avatarUrl) —
  /// there's no separate self-avatar row on this screen, unlike
  /// Thread_Detail. For an external edge (neither party is the viewer),
  /// the sender's own avatar is shown instead.
  void _openActivity(ActivityEdge edge, String headline) {
    final isExternal = edge.direction == 'external';
    showActivityCommentSheet(
      context,
      edge: edge,
      headline: headline,
      avatarUrl: isExternal ? edge.senderAvatarUrl : widget.avatarUrl,
      avatarInitial: isExternal
          ? (edge.senderZendtag?.isNotEmpty == true ? edge.senderZendtag![0].toUpperCase() : '?')
          : (widget.label.startsWith('@') ? widget.label.substring(1, 2).toUpperCase() : (widget.label.isNotEmpty ? widget.label[0].toUpperCase() : '?')),
      onViewReceipt: () => _openReceipt(edge),
    );
  }

  String _describeEdge(ActivityEdge edge, ZendAppModel model) {
    final verb = feedVerbFor(edge);
    if (edge.direction == 'external') {
      // A Shared_Network edge between the target person and someone else —
      // neither party is the viewer.
      return '${edge.senderZendtag != null ? '@${edge.senderZendtag}' : 'Someone'} $verb ${edge.recipientZendtag != null ? '@${edge.recipientZendtag}' : 'someone'}';
    }
    final isSelfSender = edge.direction == 'outgoing';
    return isSelfSender ? 'You $verb ${widget.label}' : '${widget.label} $verb';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

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
                  ZendAvatar(
                    radius: 18,
                    photoUrl: widget.avatarUrl,
                    initials: widget.label.startsWith('@') ? widget.label.substring(1, 2).toUpperCase() : (widget.label.isNotEmpty ? widget.label[0].toUpperCase() : '?'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: zt.border, height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: ZendLoader(size: 24))
                  : _error != null
                      ? Center(
                          child: Text(
                            'Could not load this person\'s activity',
                            style: TextStyle(fontFamily: 'DMSans', color: zt.textSecondary),
                          ),
                        )
                      : _edges.isEmpty
                          ? Center(
                              child: Text(
                                'No shared activity to show',
                                style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _edges.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final edge = _edges[i];
                                final headline = _describeEdge(edge, model);
                                return _PersonActivityRow(
                                  headline: headline,
                                  edge: edge,
                                  onTap: () => _openActivity(edge, headline),
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

class _PersonActivityRow extends StatelessWidget {
  const _PersonActivityRow({required this.headline, required this.edge, required this.onTap});

  final String headline;
  final ActivityEdge edge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amountLabel = edge.amountHidden ? 'Hidden' : '\$${edge.amountUsdc ?? '0'}';

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                    ),
                    if (edge.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        edge.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 12.5, color: zt.textPrimary.withValues(alpha: 0.85)),
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
