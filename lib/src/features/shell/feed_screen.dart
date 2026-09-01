import 'package:flutter/material.dart';

import '../activity/feed_content_screen.dart';

/// Feed — the primary landing tab (ZEND BETA spec §5-7, §21-24).
///
/// "What's happening between me and my people?" — a flat, mixed timeline
/// of the viewer's private Activities and their mutuals' public-to-Mutual
/// Activities, per [FeedContentScreen]. This wrapper exists only so the
/// shell's tab list has a stable "Feed" destination name independent of
/// where the actual content implementation lives.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, required this.onOpenWallet});

  /// Invoked when the user taps the header balance — Feed's one gateway
  /// into the Wallet (spec §7).
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    return FeedContentScreen(onOpenWallet: onOpenWallet);
  }
}
