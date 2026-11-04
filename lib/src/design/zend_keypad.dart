import 'package:flutter/services.dart';

/// Applies one key ('0'-'9', '.', '<' for delete) to an amount string.
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

/// Keeps a typed or pasted amount valid with the same rules as
/// [applyAmountKey]: digits and one "." only (a "," is read as "."), two
/// decimals, seven digits, no leading zero. Used with the system numpad.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var t = newValue.text.replaceAll(',', '.');
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(t)) return oldValue;
    if (t.startsWith('.')) t = '0$t';
    final dot = t.indexOf('.');
    if (dot >= 0 && t.length - dot - 1 > 2) return oldValue;
    if (t.replaceAll('.', '').length > 7) return oldValue;
    if (t.length > 1 && t.startsWith('0') && t[1] != '.') t = t.substring(1);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
