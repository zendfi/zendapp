import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import 'activity_grouping.dart';
import 'package:solar_icons/solar_icons.dart';

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
class PublicFeedScreen extends StatefulWidget {
  const PublicFeedScreen({super.key});

  @override
  State<PublicFeedScreen> createState() => _PublicFeedScreenState();
}

class _PublicFeedScreenState extends State<PublicFeedScreen> {
  bool _filterActive = false;
  String _filterQuery = '';
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _filterFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filterQuery = _filterController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _toggleFilter() {
    setState(() {
      _filterActive = !_filterActive;
      if (!_filterActive) {
        _filterController.clear();
        _filterFocus.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _filterFocus.requestFocus());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    final allPublic = model.threadedActivityEdges
        .where((e) => !e.isDirectParticipant)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Filter by sender tag, recipient tag, or note — all three because
    // the viewer is a spectator and may be searching for any party.
    final publicEdges = _filterQuery.isEmpty
        ? allPublic
        : allPublic.where((e) {
            final sender = (e.senderZendtag ?? '').toLowerCase();
            final recipient = (e.recipientZendtag ?? '').toLowerCase();
            final note = (e.note ?? '').toLowerCase();
            return sender.contains(_filterQuery) ||
                recipient.contains(_filterQuery) ||
                note.contains(_filterQuery);
          }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
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
                  IconButton(
                    onPressed: _toggleFilter,
                    icon: Icon(
                      _filterActive ? SolarIconsBold.magnifierZoomOut : SolarIconsBold.magnifier,
                      color: _filterActive ? zt.accent : zt.textSecondary,
                    ),
                    tooltip: _filterActive ? 'Clear filter' : 'Filter feed',
                  ),
                ],
              ),
            ),

            // ── Inline filter bar ──
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _filterActive
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _filterController,
                        focusNode: _filterFocus,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Filter by @handle or note…',
                          hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                          prefixIcon: Icon(SolarIconsBold.magnifier, size: 18, color: zt.textSecondary),
                          suffixIcon: _filterQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () => _filterController.clear(),
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

            Divider(color: zt.border, height: 1),

            // ── Feed ──
            Expanded(
              child: publicEdges.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _filterQuery.isNotEmpty
                              ? 'No public activity matching "$_filterQuery"'
                              : "Nothing public yet. When one of your mutuals shares an activity with their network, it shows up here.",
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
                        return _PublicPostRow(edge: edge, highlightQuery: _filterQuery);
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
  const _PublicPostRow({required this.edge, this.highlightQuery = ''});

  final ActivityEdge edge;
  final String highlightQuery;

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
    final model = ZendScope.of(context);

    // Amount is shown only when the sender opted in to sharing it (server
    // sets amount_hidden = false) AND the viewer has "show amounts on public
    // posts" enabled in their settings. Default: amounts hidden.
    final showAmount = model.showAmountOnPublicPosts && !edge.amountHidden;
    final amountLabel = '\$${edge.amountUsdc ?? '0'}';

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
                      // Amount shown inline after the headline only when opted in
                      if (showAmount)
                        TextSpan(
                          text: ' · $amountLabel',
                          style: TextStyle(color: zt.textSecondary, fontFamily: 'DMMono', fontSize: 12),
                        ),
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
        ],
      ),
    );
  }
}
