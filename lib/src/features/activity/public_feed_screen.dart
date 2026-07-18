import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import 'activity_grouping.dart';
import 'package:solar_icons/solar_icons.dart';

const _kPublicFeedEmojis = ['🔥', '💰', '🙏', '👑', '😭', '⚡', '🎯', '💸', '🎉', '👀', '✅', '🚀'];

/// Answers "where do users see public posts?" — a dedicated feed of every
/// Shared_Network Activity_Edge the viewer is authorized to see via a
/// mutual connection (i.e. `!isDirectParticipant` rows already included in
/// `ZendAppModel.threadedActivityEdges`, per Req 5.3's Shared_Network_Viewer
/// grant).
///
/// Public feed posts are read-only for comments (only sender/recipient can
/// comment, enforced server-side), but any authorized viewer may react via
/// long-press → emoji picker.
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
                        return _PublicPostRow(
                          key: ValueKey(edge.edgeId),
                          edge: edge,
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

// ── Public post row (with reactions) ─────────────────────────────────────────

class _PublicPostRow extends StatefulWidget {
  const _PublicPostRow({super.key, required this.edge});
  final ActivityEdge edge;

  @override
  State<_PublicPostRow> createState() => _PublicPostRowState();
}

class _PublicPostRowState extends State<_PublicPostRow> {
  List<EdgeReactionCount> _reactions = const [];

  String get _edgeKindStr {
    switch (widget.edge.edgeKind) {
      case ActivityEdgeKind.zendTransfer:      return 'zend_transfer';
      case ActivityEdgeKind.poolContribution:  return 'pool_contribution';
      case ActivityEdgeKind.requestFulfillment: return 'request_fulfillment';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    final model = ZendScope.of(context);
    try {
      final reactions = await model.activityDataService.getEdgeReactions(
        _edgeKindStr, widget.edge.edgeId,
      );
      if (mounted) setState(() => _reactions = reactions);
    } catch (_) {
      // Non-fatal — tile renders without reactions
    }
  }

  Future<void> _toggleReaction(String emoji) async {
    final model = ZendScope.of(context);
    final existing = _reactions.where((r) => r.emoji == emoji).firstOrNull;
    final alreadyReacted = existing?.reactedByMe ?? false;

    // Optimistic update
    setState(() {
      final updated = List<EdgeReactionCount>.of(_reactions);
      final idx = updated.indexWhere((r) => r.emoji == emoji);
      if (alreadyReacted && idx != -1) {
        final newCount = updated[idx].count - 1;
        if (newCount <= 0) {
          updated.removeAt(idx);
        } else {
          updated[idx] = EdgeReactionCount(emoji: emoji, count: newCount, reactedByMe: false);
        }
      } else if (idx != -1) {
        updated[idx] = EdgeReactionCount(emoji: emoji, count: updated[idx].count + 1, reactedByMe: true);
      } else {
        updated.add(EdgeReactionCount(emoji: emoji, count: 1, reactedByMe: true));
      }
      _reactions = updated;
    });

    try {
      if (alreadyReacted) {
        await model.activityDataService.removeEdgeReaction(_edgeKindStr, widget.edge.edgeId, emoji);
      } else {
        await model.activityDataService.addEdgeReaction(_edgeKindStr, widget.edge.edgeId, emoji);
      }
    } catch (_) {
      if (mounted) _loadReactions(); // revert on error
    }
  }

  void _showReactionPicker(BuildContext tileContext) {
    final renderBox = tileContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    double? topPosition;
    if (renderBox != null && renderBox.hasSize) {
      final globalOffset = renderBox.localToGlobal(Offset.zero);
      final msgHeight = renderBox.size.height;
      final screenHeight = MediaQuery.of(context).size.height;
      const pickerHeight = 56.0;
      if (globalOffset.dy - pickerHeight - 12 > 60) {
        topPosition = globalOffset.dy - pickerHeight - 12;
      } else {
        topPosition = (globalOffset.dy + msgHeight + 12).clamp(60.0, screenHeight - pickerHeight - 60);
      }
    }

    final reactedEmojis = _reactions.where((r) => r.reactedByMe).map((r) => r.emoji).toSet();

    entry = OverlayEntry(
      builder: (ctx) {
        final zt = ZendTheme.of(context);
        final screenHeight = MediaQuery.of(context).size.height;
        final topPos = topPosition ?? (screenHeight / 2 - 28);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => entry.remove(),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: topPos,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: zt.bgElevated,
                      borderRadius: BorderRadius.circular(ZendRadii.pill),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: zt.isDark ? 0.45 : 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final emoji in _kPublicFeedEmojis.take(8))
                          GestureDetector(
                            onTap: () {
                              entry.remove();
                              _toggleReaction(emoji);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: AnimatedScale(
                                scale: reactedEmojis.contains(emoji) ? 1.25 : 1.0,
                                duration: const Duration(milliseconds: 120),
                                child: Text(
                                  emoji,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(entry);
  }

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

    final showAmount = !widget.edge.amountHidden && widget.edge.amountUsdc != null;
    final amountLabel = '\$${widget.edge.amountUsdc ?? '0'}';
    final edge = widget.edge;

    final verb = feedVerbFor(edge);
    final senderTag = edge.senderZendtag;
    final recipientTag = edge.recipientZendtag;
    final senderLabel = senderTag != null && senderTag.isNotEmpty ? '@$senderTag' : 'Someone';
    final recipientLabel = recipientTag != null && recipientTag.isNotEmpty ? '@$recipientTag' : 'someone';
    final senderInitial = senderTag?.isNotEmpty == true ? senderTag![0].toUpperCase() : '?';

    return GestureDetector(
      // Long-press shows the inline emoji picker anchored near this tile
      onLongPress: () => _showReactionPicker(context),
      child: Container(
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
                  // ── Reaction pills ──
                  if (_reactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final r in _reactions)
                          GestureDetector(
                            onTap: () => _toggleReaction(r.emoji),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: r.reactedByMe
                                    ? zt.accent.withValues(alpha: 0.18)
                                    : zt.bgPrimary,
                                borderRadius: BorderRadius.circular(ZendRadii.pill),
                                border: r.reactedByMe
                                    ? Border.all(color: zt.accent.withValues(alpha: 0.5))
                                    : Border.all(color: zt.border),
                              ),
                              child: Text(
                                '${r.emoji} ${r.count}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  // Long-press hint — subtle, only shown when no reactions yet
                  if (_reactions.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Hold to react',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 10,
                        color: zt.textSecondary.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
