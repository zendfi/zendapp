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

/// Naira for one dollar, from `GET /api/zend/v2/fx/ngn` (the rate cash-outs
/// use). Set by [NairaRateService]; null until a rate has been seen, and then
/// money shows in dollars.
abstract final class NairaRate {
  static double? ngnPerUsd;

  /// Show amounts in Naira. Off shows dollars everywhere, as before.
  static const bool display = true;

  static bool get active => display && ngnPerUsd != null;

  /// Naira for [usd] at the current rate, or null when there is no rate.
  static double? toNgn(double usd) {
    final r = ngnPerUsd;
    return r == null ? null : usd * r;
  }
}

/// How Zend shows a balance or payment: `₦13,700` when a rate is known,
/// `$10.00` otherwise. For display only. Amount entry is still in dollars,
/// so screens where someone types an amount keep using [formatUsd].
String formatMoney(double usd, {bool signed = false}) {
  if (!NairaRate.active) return formatUsd(usd, signed: signed);
  final ngn = usd * NairaRate.ngnPerUsd!;
  // Whole Naira: kobo-level precision from a converted figure would be noise.
  final body = formatNaira(ngn.abs().roundToDouble());
  if (signed) return '${usd < 0 ? '−' : '+'}$body';
  return usd < 0 ? '−$body' : body;
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
  final frac = kobo % 100 == 0 ? '' : '.${(kobo % 100).toString().padLeft(2, '0')}';
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
