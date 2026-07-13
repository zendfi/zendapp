import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'carousel_card_model.dart';

/// Opens the Educational_Modal for a given Educational_Card (Req 26.2),
/// presented as a modal overlay rather than a full-screen navigation route
/// (Req 26.3) via `showModalBottomSheet` — the exact established pattern
/// already used throughout this codebase (`transaction_receipt_sheet.dart`,
/// `legacy_activity_list_view.dart`'s outbound-request/pending-intent
/// sheets, and the Pools/Savings/Send feature sheets).
Future<void> showEducationalModal(BuildContext context, {required CarouselCardModel card}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EducationalModalSheet(card: card),
  );
}

/// Resolves a topic's Educational_Modal body copy from its
/// `modalBodyContentRef`. v1 uses a small hardcoded lookup table rather
/// than a real copy-deck pipeline — Req 26.6 defers final copy authoring
/// outside this document, so this function is the single place that
/// mapping will be extended/replaced later.
///
/// All copy here is authored exclusively in the plain-money abstraction
/// language already used elsewhere in the Money tab and deliberately
/// excludes crypto/blockchain/stablecoin/USDC/wallet/on-chain terminology
/// (Req 26.4/26.5) — see `carousel_content_test.dart` for the supplementary
/// keyword-scan lint and tasks.md task 27.1 for the editorial checklist.
String resolveModalBody(String? ref) {
  switch (ref) {
    case 'educational_modal.why_instant.body':
      return 'When you send money on Zend, it moves straight to the other '
          "person's balance right away. There's no waiting for a bank to "
          'process anything in the background — the moment you hit send, '
          "it's already there.";
    case 'educational_modal.is_my_money_safe.body':
      return 'Your balance on Zend is held securely and is available '
          'whenever you need it. You can send, withdraw, or move it to '
          'your bank at any time — nothing is locked away without your say.';
    case 'educational_modal.sending_to_a_bank.body':
      return "When you send to a bank account, Zend handles the transfer "
          'behind the scenes and delivers the funds directly into that '
          'account. You just enter the details once and Zend takes care '
          'of getting the money there.';
    case 'educational_modal.why_balance_grows.body':
      return 'Money you keep in your Zend balance can quietly earn a bit '
          'more over time, so your balance grows on its own the longer it '
          "sits there — no extra steps needed on your end.";
    default:
      return "This topic's content is being finalized.";
  }
}

class _EducationalModalSheet extends StatelessWidget {
  const _EducationalModalSheet({required this.card});

  final CarouselCardModel card;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    // Structurally mirrors transaction_receipt_sheet.dart's _ReceiptSheet:
    // rounded-top container, drag handle, title, body content.
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
              ),
            ),
            Text(
              card.topicTitle ?? '',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              resolveModalBody(card.modalBodyContentRef),
              style: TextStyle(fontFamily: 'DMSans', fontSize: 14, height: 1.5, color: zt.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Got it',
                  style: TextStyle(fontFamily: 'DMSans', fontWeight: FontWeight.w600, color: zt.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
