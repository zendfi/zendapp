import 'package:flutter/material.dart';

import '../activity/activity_screen.dart';

/// Feed — the new primary landing tab (ZEND BETA spec §5).
///
/// "What's happening between me and my people?" not "what's my financial
/// balance?" — this is a thin wrapper around the existing [ActivityScreen]
/// (which already renders the threaded/legacy/graph activity views this
/// spec calls "Activities"), plumbing through the one new piece the spec
/// requires here: a tap on the header balance opens the Wallet.
///
/// Deliberately NOT a rewrite of ActivityScreen's body — the feed content,
/// empty/error states, and privacy-aware activity list are the subject of
/// their own dedicated redesign pass. This screen exists so the shell's tab
/// list has a stable "Feed" destination to route to today.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, required this.onOpenWallet});

  /// Invoked when the user taps the header balance — Feed's one gateway
  /// into the Wallet (spec §7).
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    return ActivityScreen(onOpenWallet: onOpenWallet);
  }
}
