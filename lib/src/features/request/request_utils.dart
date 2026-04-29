import 'dart:math';

const _base62Chars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String generateRequestId() {
  final random = Random();
  return String.fromCharCodes(
    Iterable.generate(
      8,
      (_) => _base62Chars.codeUnitAt(random.nextInt(_base62Chars.length)),
    ),
  );
}

String buildRequestLink(String username, String requestId) {
  return 'zdfi.me/@$username/$requestId';
}

String formatRequestAmount(double amount) {
  if (amount == amount.truncateToDouble()) {
    return '\$${amount.toInt()}';
  }
  return '\$${amount.toStringAsFixed(2)}';
}

double? validateAmountInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final regex = RegExp(r'^(\d+)(\.\d{1,2})?$');
  if (!regex.hasMatch(trimmed)) return null;

  final value = double.tryParse(trimmed);
  if (value == null || value <= 0) return null;

  return value;
}

bool isValidExpiryDate(DateTime date) {
  return date.isAfter(DateTime.now());
}

int remainingCharacters(String text, int maxLength) {
  return maxLength - min(text.length, maxLength);
}
