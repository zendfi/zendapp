// Supplementary keyword-scan lint for Req 26.4/26.5's crypto-terminology
// exclusion constraint on Educational_Card/Educational_Modal content.
//
// This is deliberately NOT a property test (per design.md's Property 28
// note): the input here is the fixed, hardcoded `CarouselCardModel` list
// and hardcoded `resolveModalBody()` copy — a small, finite, hand-authored
// set of strings decided outside this document (Req 26.6), not generated
// data. A literal case-insensitive substring match is a mechanical
// supplementary check that catches the most obvious violation (the literal
// excluded term appearing in shipped copy); it is NOT a substitute for the
// authoritative editorial/content review described in tasks.md task 27.1,
// since a card could avoid the literal word "wallet" while still
// describing on-chain mechanics in disguised terms — that judgment call is
// not something a fixed string-match can fully capture.

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/features/money/carousel_card_model.dart';
import 'package:zendapp/src/features/money/educational_modal.dart';

const _excludedTerms = [
  'crypto',
  'blockchain',
  'stablecoin',
  'usdc',
  'wallet',
  'on-chain',
  'onchain',
  'solana',
  'defi',
  'token',
];

void main() {
  test('no shipped Educational_Card title contains an excluded crypto-terminology term', () {
    for (final card in kEducationalCards) {
      final title = (card.topicTitle ?? '').toLowerCase();
      for (final term in _excludedTerms) {
        expect(
          title.contains(term),
          isFalse,
          reason: 'Educational_Card "${card.topicId}" title contains excluded term "$term": "$title"',
        );
      }
    }
  });

  test('no shipped Educational_Modal body copy contains an excluded crypto-terminology term', () {
    for (final card in kEducationalCards) {
      final body = resolveModalBody(card.modalBodyContentRef).toLowerCase();
      for (final term in _excludedTerms) {
        expect(
          body.contains(term),
          isFalse,
          reason: 'Educational_Modal body for "${card.topicId}" contains excluded term "$term": "$body"',
        );
      }
    }
  });
}
