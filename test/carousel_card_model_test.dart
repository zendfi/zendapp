// Example-based test for Property 25: Fixed card ordering correctness
// (Req 27.1, 25.7).
//
// No Dart property-based testing library exists in this codebase — the
// input space here is a fixed, small, hand-authored card list anyway, so
// example-based coverage of both dismissal states is both sufficient and
// appropriate (matches the same rationale used for Phase 2/3's tests).

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/features/money/carousel_card_model.dart';

void main() {
  group('buildCarouselCards (Property 25)', () {
    test('not dismissed: Debit_Card_Teaser is first, followed by kEducationalCards in fixed order', () {
      final cards = buildCarouselCards(teaserDismissed: false);

      expect(cards.first.isDebitCardTeaser, isTrue);
      expect(cards.length, kEducationalCards.length + 1);
      expect(cards.sublist(1).map((c) => c.topicId).toList(), kEducationalCards.map((c) => c.topicId).toList());
    });

    test('dismissed: carousel contains exactly kEducationalCards, no Debit_Card_Teaser', () {
      final cards = buildCarouselCards(teaserDismissed: true);

      expect(cards.any((c) => c.isDebitCardTeaser), isFalse);
      expect(cards.length, kEducationalCards.length);
      expect(cards.map((c) => c.topicId).toList(), kEducationalCards.map((c) => c.topicId).toList());
    });

    test('relative order of Educational_Cards never changes between dismissed states', () {
      final notDismissed = buildCarouselCards(teaserDismissed: false).where((c) => !c.isDebitCardTeaser).toList();
      final dismissed = buildCarouselCards(teaserDismissed: true);

      expect(notDismissed.map((c) => c.topicId).toList(), dismissed.map((c) => c.topicId).toList());
    });

    test('kEducationalCards is non-empty and every entry has a title and a modal body ref', () {
      expect(kEducationalCards, isNotEmpty);
      for (final card in kEducationalCards) {
        expect(card.topicTitle, isNotNull);
        expect(card.topicTitle, isNotEmpty);
        expect(card.modalBodyContentRef, isNotNull);
      }
    });

    test('kDebitCardTeaserCard has no title/icon/modal ref (it uses its own dedicated visual)', () {
      expect(kDebitCardTeaserCard.topicTitle, isNull);
      expect(kDebitCardTeaserCard.topicIconAsset, isNull);
      expect(kDebitCardTeaserCard.modalBodyContentRef, isNull);
    });
  });
}
