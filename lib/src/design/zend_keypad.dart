import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'zend_tokens.dart';

/// Applies one keypad key ('0'-'9', '.', '<' for delete) to an amount string.
/// Max two decimals, one dot, seven digits, no leading zero. Returns null
/// when the key is rejected.
String? applyAmountKey(String t, String key) {
  if (key == '<') return t.isEmpty ? null : t.substring(0, t.length - 1);
  if (key == '.') return t.contains('.') ? null : (t.isEmpty ? '0.' : '$t.');
  final dot = t.indexOf('.');
  if (dot >= 0 && t.length - dot > 2) return null;
  if (t.replaceAll('.', '').length >= 7) return null;
  return t == '0' ? key : '$t$key';
}

/// Numeric keypad for the amount. 44px+ touch targets, light tick per tap.
class ZendAmountKeypad extends StatelessWidget {
  const ZendAmountKeypad({super.key, required this.onKey});

  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '<'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Row(
            children: [
              for (final k in row)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: k == '<'
                        ? 'Delete'
                        : k == '.'
                        ? 'Decimal point'
                        : k,
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(ZendRadii.card),
                      onTap: () => onKey(k),
                      child: SizedBox(
                        height: 52,
                        child: Center(
                          child: k == '<'
                              ? Icon(
                                  PhosphorIconsRegular.backspace,
                                  color: zt.textPrimary,
                                )
                              : Text(
                                  k,
                                  style: ZendTextStyles.amountM.copyWith(
                                    color: zt.textPrimary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
