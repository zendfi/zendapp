import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../activity/activity_screen.dart';
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

  void _openFundDrawer(BuildContext context) {
    final model = ZendScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _FundDrawer(
          username: model.username,
          onOpenSend: () => _setTab(1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        onOpenReceive: () => _openFundDrawer(context),
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

class _FundDrawer extends StatelessWidget {
  const _FundDrawer({required this.username, required this.onOpenSend});

  final String username;
  final VoidCallback onOpenSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: ZendScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ZendSheetHandle(),
            const SizedBox(height: 20),
            const Text(
              'Fund Zend App with your link',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: ZendColors.bgDeep,
                borderRadius: BorderRadius.circular(ZendRadii.xl),
              ),
              child: Column(
                children: [
                  const Text(
                    'zdfi.me/',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      color: Color(0x80E8F4EC),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@$username',
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      color: ZendColors.textOnDeep,
                      fontSize: 32,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _QrPlaceholder(size: 120),
                  const SizedBox(height: 18),
                  Text(
                    'Scan this code to pay @$username directly.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0x99E8F4EC), fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Share payment link', onPressed: () {}),
            const SizedBox(height: 12),
            OutlineActionButton(
              label: 'Create payment request',
              onPressed: () {
                Navigator.of(context).pop();
                onOpenSend();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Colors.white,
      child: CustomPaint(painter: _QrPainter()),
    );
  }
}

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    const grid = 16;
    final cell = size.width / grid;
    final pattern = <List<int>>[
      [1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0],
      [1, 0, 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1],
      [1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0],
      [1, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1],
      [1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0],
      [0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0],
      [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1],
      [1, 1, 0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1, 0, 0],
      [0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 1],
      [1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0],
      [1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0],
      [0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1],
      [1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1],
      [0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0],
      [1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1, 1],
      [0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1],
    ];
    for (var row = 0; row < pattern.length; row++) {
      for (var col = 0; col < pattern[row].length; col++) {
        if (pattern[row][col] == 1) {
          canvas.drawRect(Rect.fromLTWH(col * cell, row * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
