import 'package:flutter/material.dart';

import 'zend_primitives.dart';
import 'zend_tokens.dart';

/// A real modal dialog for a failed action — used instead of an in-sheet
/// "error stage". A dedicated modal renders on top of whatever sheet/screen
/// is already showing without altering its own internal state, so
/// dismissing or retrying can never leave the underlying flow sitting on a
/// stale intermediate stage (the bug this replaces: Send/Request's old
/// error stage was itself a stage in the same sheet, so "Try again" moved
/// the sheet backward through its own stage history instead of just
/// retrying — see redesign.md's error-hierarchy principle, spec §60-61).
///
/// [onRetry] is optional — omit it for a case with nothing sensible to
/// retry (e.g. a definite rejection the user needs to act on differently).
Future<void> showZendErrorModal(
  BuildContext context, {
  required String message,
  String title = "Couldn't complete that",
  VoidCallback? onRetry,
  String retryLabel = 'Try again',
  VoidCallback? onDismiss,
  String dismissLabel = 'Cancel',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final zt = ZendTheme.of(dialogContext);
      return Dialog(
        backgroundColor: zt.bgPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.xxl)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 20, color: zt.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (onRetry != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: retryLabel,
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onRetry();
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlineActionButton(
                  label: dismissLabel,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onDismiss?.call();
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
