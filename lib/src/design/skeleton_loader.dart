import 'package:flutter/material.dart';
import 'zend_tokens.dart';

/// Pulsing shimmer base — wraps any widget in a smooth pulse animation.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (ctx, child) => Opacity(opacity: 0.35 + 0.45 * _anim.value, child: child),
      child: widget.child,
    );
  }
}

/// A single skeleton block — rounded rectangle placeholder.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height, this.radius = 10});
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Chat list skeleton ────────────────────────────────────────────────────────

/// Skeleton for the DM thread list — shows 5 fake conversation rows.
class DmListSkeleton extends StatelessWidget {
  const DmListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        itemCount: 6,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Avatar circle
              _SkeletonBox(width: 48, height: 48, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SkeletonBox(width: 100 + (i % 3) * 20.0, height: 13),
                        _SkeletonBox(width: 32, height: 11),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _SkeletonBox(width: 160 + (i % 2) * 30.0, height: 11),
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

// ── Chat thread skeleton ──────────────────────────────────────────────────────

/// Skeleton for a DM thread — shows a mix of sent/received bubble outlines.
class DmThreadSkeleton extends StatelessWidget {
  const DmThreadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Alternating bubble pattern mirroring a real conversation
    const bubbles = [
      (isMe: false, width: 0.55, lines: 1),
      (isMe: true,  width: 0.45, lines: 1),
      (isMe: false, width: 0.65, lines: 2),
      (isMe: true,  width: 0.55, lines: 1),
      (isMe: true,  width: 0.38, lines: 1),
      (isMe: false, width: 0.48, lines: 1),
      (isMe: false, width: 0.72, lines: 2),
      (isMe: true,  width: 0.60, lines: 1),
    ];

    final screenWidth = MediaQuery.of(context).size.width;

    // Decide which bubbles in the sequence are the last in a received run
    // (i.e. the one that gets the avatar slot). In our fixed list, mark a
    // received bubble as "last" when the *next* bubble (index+1 in the
    // reversed list) is either sent or doesn't exist.
    final reversedBubbles = bubbles.reversed.toList();

    return _Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Date separator placeholder
            Center(child: _SkeletonBox(width: 60, height: 10, radius: 5)),
            const SizedBox(height: 16),
            // Bubble rows — received bubbles include a 26px avatar circle slot
            // on the left, matching the real DmThreadScreen layout exactly.
            for (var idx = 0; idx < reversedBubbles.length; idx++) ...[
              _SkeletonBubbleRow(
                bubbleWidth: screenWidth * reversedBubbles[idx].width,
                lines: reversedBubbles[idx].lines,
                isMe: reversedBubbles[idx].isMe,
                // Show avatar circle only on the last bubble in a received run
                showAvatar: !reversedBubbles[idx].isMe &&
                    (idx == reversedBubbles.length - 1 || reversedBubbles[idx + 1].isMe),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Skeleton bubble row — matches the real DmThreadScreen layout ─────────────
// Received bubbles sit next to a 26px avatar circle (or empty slot for
// grouped messages). Sent bubbles are right-aligned with no avatar slot.

class _SkeletonBubbleRow extends StatelessWidget {
  const _SkeletonBubbleRow({
    required this.bubbleWidth,
    required this.lines,
    required this.isMe,
    this.showAvatar = false,
  });

  final double bubbleWidth;
  final int lines;
  final bool isMe;
  /// When true, renders an avatar circle on the left (last in a received run).
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );

    final bubble = Container(
      width: bubbleWidth,
      padding: EdgeInsets.symmetric(horizontal: 13, vertical: lines == 1 ? 10 : 12),
      decoration: BoxDecoration(
        color: isMe ? zt.accent.withValues(alpha: 0.25) : zt.bgSecondary,
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(6)),
          ),
          if (lines > 1) ...[
            const SizedBox(height: 5),
            Container(
              height: 12,
              width: bubbleWidth * 0.6,
              decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(6)),
            ),
          ],
        ],
      ),
    );

    if (isMe) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [bubble, const SizedBox(width: 4)],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Avatar slot — 26px circle or empty space for grouped messages
        SizedBox(
          width: 32,
          child: showAvatar
              ? Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: zt.bgSecondary,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
        bubble,
      ],
    );
  }
}



// ── Activity feed skeleton (threaded & legacy) ───────────────────────────────

/// Skeleton for both ThreadedActivityScreen and LegacyActivityListView —
/// shows 6 thread/transaction rows with avatar + name + note + amount shapes.
class ActivityFeedSkeleton extends StatelessWidget {
  const ActivityFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return _Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 7,
        itemBuilder: (ctx, i) {
          // Vary widths slightly so it doesn't look like a grid
          final nameW = 80.0 + (i % 4) * 22.0;
          final noteW = 130.0 + (i % 3) * 28.0;
          final amtW  = 40.0 + (i % 3) * 10.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar circle
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: zt.border,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(width: nameW, height: 13),
                        const SizedBox(height: 6),
                        _SkeletonBox(width: noteW, height: 11),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SkeletonBox(width: amtW, height: 13),
                      const SizedBox(height: 6),
                      _SkeletonBox(width: 28, height: 10),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Graph view skeleton ───────────────────────────────────────────────────────

/// Skeleton for GraphViewScreen — a network of faint circles and connecting
/// lines, hinting at the node/edge layout without revealing real data.
class GraphViewSkeleton extends StatelessWidget {
  const GraphViewSkeleton({super.key});

  static const _nodes = [
    // (dx, dy, radius) — relative to center of canvas, as fractions of width
    (0.0,   0.0,   22.0),   // center — "me"
    (-0.28, -0.22, 16.0),
    ( 0.30, -0.18, 16.0),
    (-0.18,  0.28, 16.0),
    ( 0.24,  0.25, 16.0),
    (-0.40,  0.05, 13.0),
    ( 0.08, -0.38, 13.0),
    (-0.10,  0.40, 13.0),
  ];

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return _Shimmer(
      child: LayoutBuilder(builder: (ctx, constraints) {
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2;
        return CustomPaint(
          painter: _GraphSkeletonPainter(
            nodes: _nodes,
            cx: cx, cy: cy,
            width: constraints.maxWidth,
            lineColor: zt.border,
            nodeColor: zt.bgSecondary,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      }),
    );
  }
}

class _GraphSkeletonPainter extends CustomPainter {
  const _GraphSkeletonPainter({
    required this.nodes,
    required this.cx,
    required this.cy,
    required this.width,
    required this.lineColor,
    required this.nodeColor,
  });

  final List<(double, double, double)> nodes;
  final double cx, cy, width;
  final Color lineColor, nodeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final nodePaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final positions = nodes.map((n) =>
      Offset(cx + n.$1 * width, cy + n.$2 * width),
    ).toList();

    // Draw lines from center to every other node
    for (var i = 1; i < positions.length; i++) {
      canvas.drawLine(positions[0], positions[i], linePaint);
    }
    // A few cross-links
    if (positions.length > 4) {
      canvas.drawLine(positions[1], positions[3], linePaint);
      canvas.drawLine(positions[2], positions[4], linePaint);
    }

    // Draw node circles on top
    for (var i = 0; i < nodes.length; i++) {
      canvas.drawCircle(positions[i], nodes[i].$3, nodePaint);
    }
  }

  @override
  bool shouldRepaint(_GraphSkeletonPainter old) => false;
}

// ── User profile skeleton ─────────────────────────────────────────────────────

/// Skeleton for UserProfileScreen — hero avatar + name + tag + action buttons.
class UserProfileSkeleton extends StatelessWidget {
  const UserProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return _Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Avatar
            Center(
              child: Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: zt.bgSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Display name
            Center(child: _SkeletonBox(width: 140, height: 22, radius: 8)),
            const SizedBox(height: 8),
            // @zendtag
            Center(child: _SkeletonBox(width: 80, height: 13, radius: 6)),
            const SizedBox(height: 8),
            // Bio lines
            Center(child: _SkeletonBox(width: 210, height: 12, radius: 6)),
            const SizedBox(height: 4),
            Center(child: _SkeletonBox(width: 160, height: 12, radius: 6)),
            const SizedBox(height: 28),
            // Action buttons row
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Stats / context card placeholder
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Savings screen skeleton ───────────────────────────────────────────────────

/// Skeleton for SavingsScreen — APY chip + large balance + two stat cards +
/// action buttons.
class SavingsSkeleton extends StatelessWidget {
  const SavingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return _Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // APY chip
            _SkeletonBox(width: 100, height: 26, radius: 13),
            const SizedBox(height: 24),
            // Label
            _SkeletonBox(width: 100, height: 13, radius: 6),
            const SizedBox(height: 8),
            // Large balance
            _SkeletonBox(width: 200, height: 58, radius: 10),
            const SizedBox(height: 32),
            // Two stat cards side by side
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 76,
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 76,
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Primary button
            Container(
              height: 52,
              width: double.infinity,
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 12),
            // Secondary button
            Container(
              height: 52,
              width: double.infinity,
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mission room (pool chat) skeleton ────────────────────────────────────────

/// Skeleton for MissionRoom chat — mirrors the real message layout with
/// avatar + sender label + bubble, same as DmThreadSkeleton but with
/// sender-name labels above each bubble.
class MissionRoomSkeleton extends StatelessWidget {
  const MissionRoomSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final w = MediaQuery.of(context).size.width;

    const rows = [
      (left: true,  bubbleW: 0.56, lines: 1),
      (left: true,  bubbleW: 0.66, lines: 2),
      (left: false, bubbleW: 0.44, lines: 1),
      (left: true,  bubbleW: 0.50, lines: 1),
      (left: false, bubbleW: 0.60, lines: 2),
      (left: false, bubbleW: 0.38, lines: 1),
      (left: true,  bubbleW: 0.72, lines: 1),
    ];

    return _Shimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Date chip
            Center(child: _SkeletonBox(width: 60, height: 10, radius: 5)),
            const SizedBox(height: 16),
            for (final r in rows.reversed) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (r.left) ...[
                    // Avatar circle
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: zt.bgSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sender name chip
                          _SkeletonBox(width: 60, height: 10, radius: 5),
                          const SizedBox(height: 4),
                          _MissionBubble(width: w * r.bubbleW, lines: r.lines, zt: zt, isLeft: true),
                        ],
                      ),
                    ),
                    SizedBox(width: w * 0.15),
                  ] else ...[
                    SizedBox(width: w * 0.15),
                    Flexible(
                      child: _MissionBubble(width: w * r.bubbleW, lines: r.lines, zt: zt, isLeft: false),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissionBubble extends StatelessWidget {
  const _MissionBubble({required this.width, required this.lines, required this.zt, required this.isLeft});
  final double width;
  final int lines;
  final ZendTheme zt;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isLeft ? 4 : 16),
          bottomRight: Radius.circular(isLeft ? 16 : 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 12, width: double.infinity,
            decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(6))),
          if (lines > 1) ...[
            const SizedBox(height: 5),
            Container(height: 12, width: width * 0.55,
              decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(6))),
          ],
        ],
      ),
    );
  }
}

// ── Search screen skeleton ────────────────────────────────────────────────────

/// Skeleton for the user search results section in SearchScreen.
class SearchUsersSkeleton extends StatelessWidget {
  const SearchUsersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return _Shimmer(
      child: Column(
        children: List.generate(4, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: zt.bgSecondary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 100 + i * 18.0, height: 13),
                    const SizedBox(height: 5),
                    _SkeletonBox(width: 70.0, height: 11),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ── Person activity screen skeleton ──────────────────────────────────────────

/// Skeleton for PersonActivityScreen — same row shape as ActivityFeedSkeleton
/// but without the card wrapper (flat list style).
class PersonActivitySkeleton extends StatelessWidget {
  const PersonActivitySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return _Shimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 6,
        separatorBuilder: (_, _) => Divider(color: zt.border, height: 1),
        itemBuilder: (ctx, i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: zt.bgSecondary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(width: 80 + (i % 3) * 24.0, height: 13),
                      const SizedBox(height: 6),
                      _SkeletonBox(width: 130 + (i % 4) * 20.0, height: 11),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _SkeletonBox(width: 44, height: 13),
                    const SizedBox(height: 6),
                    _SkeletonBox(width: 28, height: 10),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
