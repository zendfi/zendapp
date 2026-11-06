import 'package:flutter/services.dart';

/// Applies one key ('0'-'9', '.', '<' for delete) to an amount string.
/// Dollars: max two decimals, one dot, seven digits, no leading zero.
/// Naira ([naira]): whole Naira only, nine digits, grouped with commas
/// (`13,700`). Returns null when the key is rejected.
String? applyAmountKey(String t, String key, {bool naira = false}) {
  if (naira) {
    final raw = t.replaceAll(',', '');
    if (key == '<') {
      return raw.isEmpty ? null : _group(raw.substring(0, raw.length - 1));
    }
    // "000" is the Naira keypad's spare key: ₦5 → ₦5,000 in one tap.
    if (key == '000') {
      if (raw.isEmpty || raw == '0' || raw.length + 3 > 9) return null;
      return _group('${raw}000');
    }
    if (key == '.' || raw.length >= 9) return null;
    return _group(raw == '0' || raw.isEmpty ? key : '$raw$key');
  }
  if (key == '<') return t.isEmpty ? null : t.substring(0, t.length - 1);
  if (key == '.') return t.contains('.') ? null : (t.isEmpty ? '0.' : '$t.');
  final dot = t.indexOf('.');
  if (dot >= 0 && t.length - dot > 2) return null;
  if (t.replaceAll('.', '').length >= 7) return null;
  return t == '0' ? key : '$t$key';
}

String _group(String digits) {
  final d = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return d.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// Keeps a typed or pasted amount valid with the same rules as
/// [applyAmountKey]. Dollars: digits and one "." only (a "," is read as
/// "."), two decimals, seven digits, no leading zero. Naira ([naira]): whole
/// Naira, nine digits, shown with thousands commas. Used with the system
/// numpad.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.naira = false});

  final bool naira;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (naira) {
      // Whole Naira: drop separators, refuse anything but digits.
      var raw = newValue.text.replaceAll(',', '');
      if (raw.contains('.')) raw = raw.substring(0, raw.indexOf('.'));
      if (!RegExp(r'^\d*$').hasMatch(raw) || raw.length > 9) return oldValue;
      final t = raw.isEmpty ? '' : _group(raw);
      return TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
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
