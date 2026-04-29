import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../request/request_drawer_sheet.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Receive',
                style: const TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: ZendColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: ZendScrollPage(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: ZendColors.bgDeep,
                          borderRadius: BorderRadius.circular(ZendRadii.xl),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'zdfi.me/',
                              style: const TextStyle(
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
                            const _QrCard(size: 120),
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
                      OutlineActionButton(label: 'Create payment request', onPressed: () => showRequestDrawer(context)),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          'Customise your page',
                          style: const TextStyle(fontFamily: 'DMSans', color: ZendColors.accent, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.size});

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
