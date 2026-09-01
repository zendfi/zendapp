import 'package:flutter/material.dart';

import '../money/home_screen.dart';

/// Wallet — reached only by tapping the balance on Feed (ZEND BETA spec
/// §7-8: "The balance on the feed is a gateway... Tap → Wallet"). Not a
/// shell tab; always a pushed screen with a back arrow.
///
/// This is a thin wrapper around the existing [HomeScreen] body, which
/// already renders the balance hero, Savings/Pools cards, and Recent
/// section this screen needs — just with its header's back button turned
/// on, since HomeScreen previously only ever lived as a bare shell tab
/// with no route to pop. Bringing Wallet's visuals fully in line with the
/// spec's own restrained-dashboard wireframe (§8-9 — Cards/Withdraw rows,
/// error states) is scoped as its own follow-up screen pass, not part of
/// the nav restructure.
class WalletScreen extends StatelessWidget {
  const WalletScreen({
    super.key,
    required this.onOpenReceive,
    required this.onOpenWithdraw,
    required this.onViewAll,
  });

  final VoidCallback onOpenReceive;
  final VoidCallback onOpenWithdraw;

  /// "View all" from within Wallet's Recent section — pops back to Feed,
  /// since Feed (not a Wallet sub-screen) is now where the full Activity
  /// list lives.
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      showBackButton: true,
      onOpenReceive: onOpenReceive,
      onOpenWithdraw: onOpenWithdraw,
      onViewAll: onViewAll,
    );
  }
}
