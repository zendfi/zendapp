import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/appkit_service.dart';

/// The only place a ZApp's money action is approved. Rendered by Zend from
/// what the bridge received, so the app can't restyle or hide anything.
/// Copy follows the plain-language rule: no crypto words.
Future<bool> confirmZAppMoney(
  BuildContext context, {
  required ZAppDescriptor app,
  required String title,
  required String amountLabel,
  String? recipient,
  String? note,
  String? custodyName,

  /// For a payment that pays several people: each person and their amount,
  /// already formatted ("₦1,800"). Shown under the total.
  List<(String, String)>? parts,
}) async {
  final ok = await showZendModalSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _ConfirmBody(
      app: app,
      title: title,
      amountLabel: amountLabel,
      recipient: recipient,
      note: note,
      custodyName: custodyName,
      parts: parts,
    ),
  );
  return ok == true;
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.app,
    required this.title,
    required this.amountLabel,
    this.recipient,
    this.note,
    this.custodyName,
    this.parts,
  });
  final List<(String, String)>? parts;
  final ZAppDescriptor app;
  final String title;
  final String amountLabel;
  final String? recipient;
  final String? note;
  final String? custodyName;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final custody = custodyName != null
        ? 'Goes straight to $custodyName. Zend can\'t get it back.'
        : app.custody == 'creator'
        ? 'Goes straight to the person who made this. Zend can\'t get it back.'
        : null;
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: zt.bgSecondary,
                  backgroundImage: app.iconUrl != null
                      ? NetworkImage(app.iconUrl!)
                      : null,
                  child: app.iconUrl == null
                      ? Icon(
                          PhosphorIconsRegular.squaresFour,
                          size: 14,
                          color: zt.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(app.name, style: s(14, w: FontWeight.w600)),
                ),
              ],
            ),
            if (app.trustLabel != null) ...[
              const SizedBox(height: 6),
              Text(app.trustLabel!, style: s(12, c: zt.textSecondary)),
            ],
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: s(16, c: zt.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              amountLabel,
              textAlign: TextAlign.center,
              style: s(36, w: FontWeight.w700),
            ),
            if (recipient != null) ...[
              const SizedBox(height: 4),
              Text(
                'to $recipient',
                textAlign: TextAlign.center,
                style: s(16, w: FontWeight.w600),
              ),
            ],
            if (parts != null) ...[
              const SizedBox(height: 12),
              for (final (who, amount) in parts!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(who, style: s(15))),
                      Text(amount, style: s(15, w: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
            if (note != null && note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"$note"',
                textAlign: TextAlign.center,
                style: s(14, c: zt.textSecondary),
              ),
            ],
            if (custody != null) ...[
              const SizedBox(height: 16),
              Text(
                custody,
                textAlign: TextAlign.center,
                style: s(12, c: zt.textSecondary),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Confirm',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: s(14, c: zt.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
