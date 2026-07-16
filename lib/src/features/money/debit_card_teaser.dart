import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

/// A single, non-functional, "coming soon" carousel card styled to resemble
/// a physical debit card (Req 25.2) — a chip graphic, hologram-style
/// detailing, and a card-network mark placeholder, all synthetic. Contains
/// no real card number, expiration date, CVV, or cardholder name (Req 25.3)
/// and has no functional card action beyond the explicit dismiss control
/// (Req 25.4) — the card body itself is otherwise inert.
class DebitCardTeaser extends StatelessWidget {
  const DebitCardTeaser({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // Dark green-to-black — on-brand with ZendColors.bgDeep.
          colors: [Color(0xFF1B3A2E), Color(0xFF0E241C)],
        ),
      ),
      child: Stack(
        children: [
          // Chip graphic — upper-left, rounded rectangle.
          Positioned(
            top: 4,
            left: 0,
            child: Container(
              width: 34,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(colors: [Color(0xFFD4C08A), Color(0xFFA9955F)]),
              ),
            ),
          ),
          // Hologram-style detail — small iridescent circle, upper-right.
          Positioned(
            top: 0,
            right: 36,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0x99FFFFFF), Color(0x33FFFFFF)]),
              ),
            ),
          ),
          // Card-network mark placeholder — generic two-circle glyph, bottom-right.
          Positioned(
            bottom: 4,
            right: 0,
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x55F0F0F0)),
                ),
                Transform.translate(
                  offset: const Offset(-6, 0),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33F0F0F0)),
                  ),
                ),
              ],
            ),
          ),
          // "Coming soon" label.
          const Positioned(
            bottom: 4,
            left: 0,
            child: Text(
              'Zend Card — coming soon',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: Color(0xD9F0F0F0)),
            ),
          ),
          // Dismiss control (Req 25.5).
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: onDismiss,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(SolarIconsBold.closeCircle, size: 16, color: Color(0x99F0F0F0)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
