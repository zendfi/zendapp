import 'package:flutter/material.dart';

import 'carousel_card_model.dart';
import 'debit_card_teaser.dart';
import 'educational_card_tile.dart';

/// The horizontally swipeable, snapping card row on the Money_Home_Screen
/// (Req 24). Renders the fixed [cards] sequence via a `PageView` with a
/// fractional `viewportFraction` — Flutter's built-in paging widget already
/// snaps to the nearest page boundary by construction (Req 24.2/24.3),
/// distinct from the non-snapping `ListView.separated` pattern used
/// elsewhere for filter pills (Req 24.4). See design.md's "Carousel
/// implementation approach" decision for the full tradeoff analysis.
class CardCarousel extends StatelessWidget {
  const CardCarousel({super.key, required this.cards, required this.onCardTap, required this.onDismissTeaser});

  final List<CarouselCardModel> cards;
  final void Function(CarouselCardModel card) onCardTap;
  final VoidCallback onDismissTeaser;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      // Matches _SavingsCard/_PoolsCard height (118) plus carousel breathing room.
      height: 150,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.88),
        padEnds: false,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: card.isDebitCardTeaser
                ? DebitCardTeaser(onDismiss: onDismissTeaser)
                : EducationalCardTile(card: card, onTap: () => onCardTap(card)),
          );
        },
      ),
    );
  }
}
