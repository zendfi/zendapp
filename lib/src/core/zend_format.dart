/// The one place money, dates and people are turned into display text.
///
/// Every screen used to carry its own copy of these (four "$1 if whole, else
/// $1.50" helpers, several `month/day` date strings, many hand-built
/// `'@$tag'` labels), which is why the same payment read as "$1" on the Feed
/// and "$1.00" on the Receipt. New display code should call these; don't add
/// local variants.
library;

/// `$1,250.00` — always two decimals, thousands separators, `$` symbol.
/// [signed] adds `+`/`−` so direction never relies on colour alone.
String formatUsd(double amount, {bool signed = false}) {
  final negative = amount < 0;
  final cents = (amount.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final frac = (cents % 100).toString().padLeft(2, '0');
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final body = '\$$grouped.$frac';
  if (signed) return '${negative ? '−' : '+'}$body';
  return negative ? '−$body' : body;
}

/// How amounts are shown: the person's own currency. Balances and payments are
/// held and moved in dollars; this converts for display and for typing.
///
/// [code] comes from `GET /api/zend/v2/me/currency` (chosen from where the
/// person signed up, changeable in Profile). [rates] is every currency per
/// dollar from `GET /api/zend/v2/fx/rates`. Both are kept on the device, so
/// a missing network never flips the app back to dollars.
abstract final class DisplayCurrency {
  /// ISO code, e.g. `NGN`, `EUR`, `KES`. `USD` until known.
  static String code = 'USD';

  /// Units of each currency for one dollar. Always has `USD: 1`.
  static Map<String, double> rates = {'USD': 1};

  /// Units of [code] per dollar, or null when there's no rate for it yet.
  static double? get rate => code == 'USD' ? 1 : rates[code];

  /// Converting from dollars (any currency but dollars, with a rate).
  static bool get active => code != 'USD' && rate != null;

  static bool get isNaira => code == 'NGN' && rate != null;

  /// [usd] in the display currency, or null without a rate.
  static double? fromUsd(double usd) {
    final r = rate;
    return r == null ? null : usd * r;
  }
}

/// The Naira rate on its own, for things that are always in Naira whatever
/// the person's currency (bank transfers in Nigeria, prices set in Naira).
abstract final class NairaRate {
  static double? get ngnPerUsd => DisplayCurrency.rates['NGN'];
  static set ngnPerUsd(double? r) {
    if (r == null) return;
    DisplayCurrency.rates = {...DisplayCurrency.rates, 'NGN': r};
  }

  /// Showing amounts in Naira right now.
  static bool get active => DisplayCurrency.isNaira;

  static double? toNgn(double usd) {
    final r = ngnPerUsd;
    return r == null ? null : usd * r;
  }
}

/// How a currency is written: its symbol (null: write the code, `KES 1,290`)
/// and whether amounts are whole units (no cents worth typing).
class CurrencyStyle {
  const CurrencyStyle(this.symbol, {this.whole = false});
  final String? symbol;
  final bool whole;

  static const _styles = <String, CurrencyStyle>{
    'USD': CurrencyStyle('\$'),
    'NGN': CurrencyStyle('₦', whole: true),
    'EUR': CurrencyStyle('€'),
    'GBP': CurrencyStyle('£'),
    'JPY': CurrencyStyle('¥', whole: true),
    'CNY': CurrencyStyle('CN¥'),
    'INR': CurrencyStyle('₹', whole: true),
    'KRW': CurrencyStyle('₩', whole: true),
    'GHS': CurrencyStyle('GH₵'),
    'ZAR': CurrencyStyle('R'),
    'CAD': CurrencyStyle('CA\$'),
    'AUD': CurrencyStyle('A\$'),
    'NZD': CurrencyStyle('NZ\$'),
    'SGD': CurrencyStyle('S\$'),
    'HKD': CurrencyStyle('HK\$'),
    'MXN': CurrencyStyle('MX\$'),
    'BRL': CurrencyStyle('R\$'),
    'TRY': CurrencyStyle('₺'),
    'PHP': CurrencyStyle('₱'),
    'UAH': CurrencyStyle('₴'),
    'ILS': CurrencyStyle('₪'),
    'THB': CurrencyStyle('฿'),
    'PLN': CurrencyStyle('zł'),
    'VND': CurrencyStyle('₫', whole: true),
    'KES': CurrencyStyle(null, whole: true),
    'UGX': CurrencyStyle(null, whole: true),
    'TZS': CurrencyStyle(null, whole: true),
    'RWF': CurrencyStyle(null, whole: true),
    'XOF': CurrencyStyle(null, whole: true),
    'XAF': CurrencyStyle(null, whole: true),
    'IDR': CurrencyStyle(null, whole: true),
    'CLP': CurrencyStyle(null, whole: true),
    'COP': CurrencyStyle(null, whole: true),
    'PYG': CurrencyStyle(null, whole: true),
    'HUF': CurrencyStyle(null, whole: true),
    'ISK': CurrencyStyle(null, whole: true),
    'PKR': CurrencyStyle(null, whole: true),
    'LKR': CurrencyStyle(null, whole: true),
    'NPR': CurrencyStyle(null, whole: true),
    'BDT': CurrencyStyle(null, whole: true),
    'MWK': CurrencyStyle(null, whole: true),
    'ZMW': CurrencyStyle(null),
    'ETB': CurrencyStyle(null),
    'EGP': CurrencyStyle(null),
  };

  static CurrencyStyle of(String code) =>
      _styles[code] ?? const CurrencyStyle(null);

  /// Prefix for an amount: `₦`, `€`, or `KES ` when there's no symbol.
  static String prefixOf(String code) => of(code).symbol ?? '$code ';
}

/// Dollars for a Naira figure, to the smallest unit of the balance (6 dp),
/// not to the cent: ₦1,000 must arrive as ₦1,000, and a cent is ~₦14.
double nairaToUsd(double ngn, double ngnPerUsd) =>
    (ngn / ngnPerUsd * 1000000).round() / 1000000;

/// What someone types an amount in on one entry screen. Fixed when the
/// screen opens, so the unit never changes under their fingers: the person's
/// currency when it has a rate, dollars otherwise.
class AmountEntry {
  AmountEntry._(this.code, this.perUsd);

  /// The display currency when it has a rate, else dollars.
  factory AmountEntry.current() => DisplayCurrency.active
      ? AmountEntry._(DisplayCurrency.code, DisplayCurrency.rate)
      : AmountEntry._('USD', null);

  /// Always dollars (cash-out, providers, protocol amounts).
  factory AmountEntry.dollars() => AmountEntry._('USD', null);

  /// Always Naira (paying a Nigerian bank), when a Naira rate is known.
  factory AmountEntry.naira() => NairaRate.ngnPerUsd == null
      ? AmountEntry._('USD', null)
      : AmountEntry._('NGN', NairaRate.ngnPerUsd);

  final String code;

  /// Units of [code] per dollar; null for dollars.
  final double? perUsd;

  /// Typed in whole units (no decimals), e.g. Naira, Yen, Shillings.
  bool get whole => perUsd != null && CurrencyStyle.of(code).whole;

  /// Typed in a currency other than dollars.
  bool get converting => perUsd != null;

  String get symbol => perUsd == null ? '\$' : CurrencyStyle.prefixOf(code);

  /// The typed text as a number. Commas are separators.
  double typed(String text) =>
      double.tryParse(text.trim().replaceAll(',', '')) ?? 0;

  /// Dollars for the typed text, to 6 dp. When [cap] is given (the balance)
  /// and the typed amount is within one unit of it, the cap is used, so
  /// typing the balance as shown sends all of it.
  double usd(String text, {double? cap}) {
    final t = typed(text);
    if (t <= 0) return t;
    final r = perUsd;
    final usd = r == null ? t : (t / r * 1000000).round() / 1000000;
    // One shown unit (a cent, or one whole Naira/Yen...) in dollars.
    final unitUsd = r == null ? 0.01 : (whole ? 1.0 : 0.01) / r;
    // Typing the balance as shown (rounded down, or the old rounded-up
    // figure) sends all of it, rather than failing by a fraction.
    if (cap != null && cap > 0 && (usd - cap).abs() < unitUsd + 1e-9) {
      return cap;
    }
    return usd;
  }

  /// Text to put in the field for a dollar amount (prefill).
  String textFor(double usd) {
    final r = perUsd;
    if (r == null) return usd.toStringAsFixed(2);
    if (whole) return groupThousands((usd * r).round().toString());
    return (usd * r).toStringAsFixed(2);
  }

  /// [formatMoney] for a dollar figure on this screen, consistent with the
  /// unit being typed.
  String format(double usd) =>
      perUsd == null ? formatUsd(usd) : formatCurrency(usd * perUsd!, code);

  /// [format] for a balance: rounded down, so it's never more than is there.
  String formatBalance(double usd) {
    final local = perUsd == null ? usd : usd * perUsd!;
    final c = perUsd == null ? 'USD' : code;
    return formatCurrency(_floorShown(local, c), c);
  }
}

/// `1234567` → `1,234,567`.
String groupThousands(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// An amount already in [code]: `₦13,700`, `€9.20`, `KES 1,290`. Whole-unit
/// currencies drop the cents; so do others once over 1,000 (except the few
/// where cents still matter at that size).
/// Whether [amount] in [code] is shown without cents.
bool _showsWhole(double amount, String code) {
  if (code == 'USD') return false;
  const keepCents = {'EUR', 'GBP', 'CHF', 'CAD', 'AUD', 'NZD', 'SGD', 'KWD', 'BHD', 'OMR', 'JOD'};
  return CurrencyStyle.of(code).whole ||
      (amount.abs() >= 1000 && !keepCents.contains(code));
}

/// [amount] rounded down to what's shown for [code]: whole units or cents.
double _floorShown(double amount, String code) {
  if (amount <= 0) return amount;
  return _showsWhole(amount, code)
      ? (amount + 1e-7).floorToDouble()
      : (amount * 100 + 1e-6).floorToDouble() / 100;
}

String formatCurrency(double amount, String code, {bool signed = false}) {
  if (code == 'USD') return formatUsd(amount, signed: signed);
  final whole = _showsWhole(amount, code);
  final abs = amount.abs();
  final body = whole
      ? groupThousands(abs.round().toString())
      : () {
          final cents = (abs * 100).round();
          return '${groupThousands((cents ~/ 100).toString())}.'
              '${(cents % 100).toString().padLeft(2, '0')}';
        }();
  final text = '${CurrencyStyle.prefixOf(code)}$body';
  if (signed) return '${amount < 0 ? '−' : '+'}$text';
  return amount < 0 ? '−$text' : text;
}

/// How Zend shows a balance: like [formatMoney], but rounded **down**, so it's
/// never more than is there. A balance of $1.2378 shows as $1.23, not $1.24,
/// and typing what's shown always works (amount entry treats it as "all of
/// it", see [AmountEntry.usd]).
String formatBalance(double usd) {
  final local = DisplayCurrency.fromUsd(usd);
  if (local == null || DisplayCurrency.code == 'USD') {
    return formatUsd(_floorShown(usd, 'USD'));
  }
  return formatCurrency(
    _floorShown(local, DisplayCurrency.code),
    DisplayCurrency.code,
  );
}

/// A dollar balance rounded down to the cent: what can actually be sent on
/// screens that take dollars.
double floorToCent(double usd) => _floorShown(usd, 'USD');

/// How Zend shows a balance or payment: in the person's currency when it has
/// a rate (`₦13,700`, `€9.20`), dollars otherwise. Screens where someone
/// types an amount use [AmountEntry], which follows the same rule.
String formatMoney(double usd, {bool signed = false}) {
  final local = DisplayCurrency.fromUsd(usd);
  if (local == null || DisplayCurrency.code == 'USD') {
    return formatUsd(usd, signed: signed);
  }
  return formatCurrency(local, DisplayCurrency.code, signed: signed);
}

/// `₦7,850` — whole Naira with thousands separators. Kobo are only shown when
/// the amount isn't whole (`₦12.50`).
String formatNaira(double amount) {
  final negative = amount < 0;
  final kobo = (amount.abs() * 100).round();
  final whole = (kobo ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final frac = kobo % 100 == 0
      ? ''
      : '.${(kobo % 100).toString().padLeft(2, '0')}';
  return '${negative ? '−' : ''}₦$whole$frac';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Compact list timestamp: `now`, `5m`, `3h`, `Yesterday`, `4d`, then
/// `Sep 5` (or `Sep 5, 2025` in another year). Never `9/5`, whose day/month
/// order is ambiguous outside the US.
String formatRelativeTime(DateTime dt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = dt.toLocal();
  final diff = n.difference(local);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && local.day == n.day) return '${diff.inHours}h';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d';
  return formatDate(local, now: n);
}

/// `Sep 5` / `Sep 5, 2025`.
String formatDate(DateTime dt, {DateTime? now}) {
  final local = dt.toLocal();
  final n = now ?? DateTime.now();
  final base = '${_months[local.month - 1]} ${local.day}';
  return local.year == n.year ? base : '$base, ${local.year}';
}

/// `Sep 7, 2026 · 7:02 PM` — for detail screens, where the time matters.
String formatDateTime(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '${_months[l.month - 1]} ${l.day}, ${l.year} · $h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// Day-group header for feeds: `Today`, `Yesterday`, then [formatDate].
String formatDayGroup(DateTime dt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final l = dt.toLocal();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(l.year, l.month, l.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return formatDate(l, now: n);
}

/// The name to show for a person: display name, else `@handle`, else the
/// part of an email before the `@`. An email is never shown as an identity.
String personName({String? displayName, String? handle}) {
  final name = displayName?.trim() ?? '';
  if (name.isNotEmpty && !name.contains('@')) return name;
  final h = handle?.trim() ?? '';
  if (h.isEmpty) return name.isNotEmpty ? _emailLocal(name) : 'Zend user';
  return h.contains('@') ? _emailLocal(h) : '@$h';
}

/// Initial for a generated avatar, from the same source as [personName], so
/// a person's avatar letter always matches their name.
String personInitial({String? displayName, String? handle}) {
  final n = personName(displayName: displayName, handle: handle);
  final s = n.startsWith('@') ? n.substring(1) : n;
  return s.isEmpty ? '?' : s[0].toUpperCase();
}

String _emailLocal(String email) {
  final local = email.split('@').first.trim();
  return local.isEmpty ? 'Zend user' : local;
}
