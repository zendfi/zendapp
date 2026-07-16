import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'carousel_card_model.dart';
import 'package:solar_icons/solar_icons.dart';

/// The card-face widget for an Educational_Card in the Card_Carousel.
/// Tapping opens the Educational_Modal (Req 26.2) via the [onTap] callback
/// supplied by `CardCarousel`.
class EducationalCardTile extends StatelessWidget {
  const EducationalCardTile({super.key, required this.card, required this.onTap});

  final CarouselCardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: zt.isDark ? ZendColors.bgDeep : zt.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(SolarIconsBold.lightbulb, size: 20, color: zt.accent),
            Text(
              card.topicTitle ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            Text(
              'Tap to learn more',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
