/// Card data model + fixed ordering logic for the Phase 4 Money tab
/// Card_Carousel (Req 21, Req 27). Kept free of Flutter widget imports so
/// `buildCarouselCards` is directly unit-testable, matching the pattern
/// established by `activity_grouping.dart`/`graph_model.dart` in Phases 2/3.
library;

enum CarouselCardKind { debitCardTeaser, educational }

/// A single card in the Card_Carousel — either the one-off Debit_Card_Teaser
/// or an Educational_Card. Modeled as one sum-shaped class (per design.md's
/// decision 4) so `CardCarousel` can iterate a single fixed
/// `List<CarouselCardModel>` without branching at the list level.
class CarouselCardModel {
  const CarouselCardModel({
    required this.kind,
    required this.topicId,
    this.topicTitle,
    this.topicIconAsset,
    this.modalBodyContentRef,
  });

  final CarouselCardKind kind;

  /// Stable identifier for this card, e.g. `'debit_card_teaser'`,
  /// `'why_instant'`. Used for the fixed-order list (Req 27) and as the
  /// lookup key into wherever topic copy ends up living once authored
  /// (Req 26.6).
  final String topicId;

  /// Card-face title. Null for the Debit_Card_Teaser, which has its own
  /// dedicated visual rather than a generic title/icon layout.
  final String? topicTitle;

  /// Reference to an icon/illustration asset for an Educational_Card's face.
  final String? topicIconAsset;

  /// Reference to where this topic's Educational_Modal body content lives
  /// (e.g. a copy-deck key) — intentionally a reference, not the literal
  /// string, since Req 26.6 defers copy authoring outside this document.
  final String? modalBodyContentRef;

  bool get isDebitCardTeaser => kind == CarouselCardKind.debitCardTeaser;
}

/// Req 27.1-27.3: the fixed, hardcoded v1 Educational_Card ordering. No
/// backend call, no personalization — this list literally is the ordering.
///
/// Copy authored per Req 26.4/26.5's plain-money-language constraint (no
/// crypto/blockchain/stablecoin/USDC/wallet/on-chain terminology) — see
/// `carousel_content_test.dart`'s keyword-scan lint plus the editorial
/// review checklist noted in tasks.md task 27.1.
const List<CarouselCardModel> kEducationalCards = [
  CarouselCardModel(
    kind: CarouselCardKind.educational,
    topicId: 'why_instant',
    topicTitle: 'Why did that feel instant?',
    topicIconAsset: 'assets/carousel/why_instant.png',
    modalBodyContentRef: 'educational_modal.why_instant.body',
  ),
  CarouselCardModel(
    kind: CarouselCardKind.educational,
    topicId: 'is_my_money_safe',
    topicTitle: 'Is my money safe?',
    topicIconAsset: 'assets/carousel/money_safe.png',
    modalBodyContentRef: 'educational_modal.is_my_money_safe.body',
  ),
  CarouselCardModel(
    kind: CarouselCardKind.educational,
    topicId: 'sending_to_a_bank',
    topicTitle: 'What happens when I send to a bank account?',
    topicIconAsset: 'assets/carousel/sending_to_a_bank.png',
    modalBodyContentRef: 'educational_modal.sending_to_a_bank.body',
  ),
  CarouselCardModel(
    kind: CarouselCardKind.educational,
    topicId: 'why_balance_grows',
    topicTitle: 'Why does my balance grow over time?',
    topicIconAsset: 'assets/carousel/why_balance_grows.png',
    modalBodyContentRef: 'educational_modal.why_balance_grows.body',
  ),
  // Additional topics appended here in fixed order as copy is authored (Req 26.6).
];

const CarouselCardModel kDebitCardTeaserCard = CarouselCardModel(
  kind: CarouselCardKind.debitCardTeaser,
  topicId: 'debit_card_teaser',
);

/// Req 25.1/25.7/27.1: builds the fixed card sequence given dismissal
/// state. The Debit_Card_Teaser occupies the first position when not
/// dismissed; when dismissed, the carousel contains only Educational_Cards
/// in their fixed order — that relative order never changes between the
/// two cases (Property 25).
List<CarouselCardModel> buildCarouselCards({required bool teaserDismissed}) => [
      if (!teaserDismissed) kDebitCardTeaserCard,
      ...kEducationalCards,
    ];
