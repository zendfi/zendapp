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

    return _Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Date separator placeholder
            Center(child: _SkeletonBox(width: 60, height: 10, radius: 5)),
            const SizedBox(height: 16),
            // Bubble placeholders
            ...bubbles.reversed.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: b.isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: _SkeletonBubble(
                  width: screenWidth * b.width,
                  lines: b.lines,
                  isMe: b.isMe,
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBubble extends StatelessWidget {
  const _SkeletonBubble({required this.width, required this.lines, required this.isMe});
  final double width;
  final int lines;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: 13, vertical: lines == 1 ? 10 : 12),
      decoration: BoxDecoration(
        color: isMe
            ? zt.accent.withValues(alpha: 0.25)
            : zt.bgSecondary,
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 12, width: double.infinity, decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(6))),
          if (lines > 1) ...[
            const SizedBox(height: 5),
            Container(height: 12, width: width * 0.6, decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(6))),
          ],
        ],
      ),
    );
  }
}
