import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../activity/activity_screen.dart';
import '../receive/receive_screen.dart';
import '../send/send_flow_sheet.dart';
import '../send/send_screen.dart';
import '../money/home_screen.dart';

class ZendShell extends StatefulWidget {
  const ZendShell({super.key});

  @override
  State<ZendShell> createState() => _ZendShellState();
}

class _ZendShellState extends State<ZendShell> {
  int _tabIndex = 0;

  void _setTab(int index) {
    if (index == _tabIndex) return;
    setState(() {
      _tabIndex = index;
    });
  }

  Future<void> _openRecipientSheet(BuildContext context, double amount) {
    return showSendFlowSheet(context, amount: amount);
  }

  void _openReceiveScreen(BuildContext context) {
    final model = ZendScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiveScreen(username: model.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        onOpenReceive: () => _openReceiveScreen(context),
        onOpenSend: () => _setTab(1),
        onViewAll: () => _setTab(2),
      ),
      SendScreen(
        onOpenRecipients: (amount) => _openRecipientSheet(context, amount),
      ),
      const ActivityScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: pages,
      ),
      bottomNavigationBar: ZendBottomBar(
        currentIndex: _tabIndex,
        onChanged: _setTab,
      ),
    );
  }
}

class ZendBottomBar extends StatelessWidget {
  const ZendBottomBar({super.key, required this.currentIndex, required this.onChanged});

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: ZendColors.bgDeep,
        border: Border(top: BorderSide(color: Color(0x14000000))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomNavIcon(
              icon: Icons.account_balance_wallet_outlined,
              active: currentIndex == 0,
              onTap: () => onChanged(0),
            ),
            _BottomNavIcon(
              icon: Icons.attach_money,
              active: currentIndex == 1,
              onTap: () => onChanged(1),
            ),
            _BottomNavIcon(
              icon: Icons.access_time,
              active: currentIndex == 2,
              onTap: () => onChanged(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({required this.icon, required this.active, required this.onTap});

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? ZendColors.accentPop : const Color(0x66E8F4EC), size: 24),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: ZendColors.accentPop, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
