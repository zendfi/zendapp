/// Rules for choosing a Ziro PIN [R4.8]. The PIN itself never leaves this
/// screen except encrypted to the matcher.
library;

/// PINs people pick most often, beyond the patterns caught below.
const Set<String> kZiroCommonPins = {
  '0000', '1111', '1212', '1234', '1004', '2000', '2580', '0852', '6969',
  '1122', '1313', '4444', '7777', '1010', '2222', '5555', '6666', '8888',
  '9999', '3333', '1230', '0123', '4321', '2468', '1357', '1984', '1986',
  '1990', '2001', '2020', '2121', '5683', '0007', '1112', '0101', '1100',
  '0911', '0001', '9876', '6789', '7890', '1000', '2323', '1414', '4545',
};

/// Null when [pin] is fine, else the reason in plain words.
String? ziroPinProblem(String pin) {
  if (!RegExp(r'^\d{4}$').hasMatch(pin)) return 'Use 4 numbers.';
  final d = pin.codeUnits.map((c) => c - 48).toList();
  if (d.every((x) => x == d.first)) {
    return 'That PIN is easy to guess. Try one without repeated numbers.';
  }
  var up = true;
  var down = true;
  for (var i = 1; i < 4; i++) {
    if (d[i] != (d[i - 1] + 1) % 10) up = false;
    if (d[i] != (d[i - 1] + 9) % 10) down = false;
  }
  if (up || down) {
    return 'That PIN is easy to guess. Try one that isn\'t in order.';
  }
  if (kZiroCommonPins.contains(pin)) {
    return 'That PIN is one lots of people use. Try another.';
  }
  return null;
}

/// Problem with the second entry, or null when it matches the first.
String? ziroPinConfirmProblem(String first, String second) =>
    first == second ? null : "Those PINs didn't match. Try again.";
