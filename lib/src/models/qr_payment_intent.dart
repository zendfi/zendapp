/// A parsed, typed representation of a scanned or deep-linked `zdfi.me` URL.
///
/// Supported URL patterns:
///   `https://zdfi.me/@{zendtag}`                    → open intent
///   `https://zdfi.me/{zendtag}`                     → open intent (legacy backend format)
///   `https://zdfi.me/@{zendtag}?amount=X&note=Y`    → fixed-amount intent
///   `https://zdfi.me/{zendtag}/{request_link_id}`   → request link intent
///   `zendapp://pay?zendtag=...&amount=...&note=...&request_id=...` → custom scheme
///
/// This is a pure Dart value class with no Flutter dependencies.
class QrPaymentIntent {
  /// The recipient's zendtag (lowercase, no '@' prefix).
  final String zendtag;

  /// The payment amount in USDC, or null for open payments.
  final double? amountUsdc;

  /// An optional note/description for the payment (URL-decoded).
  final String? note;

  /// The request link ID for request-link intents, or null otherwise.
  final String? requestLinkId;

  const QrPaymentIntent({
    required this.zendtag,
    this.amountUsdc,
    this.note,
    this.requestLinkId,
  });

  /// Parses a [Uri] into a [QrPaymentIntent].
  ///
  /// Returns null if the URI does not match any recognised pattern.
  ///
  /// Accepts both `/@{zendtag}` (app-generated) and `/{zendtag}` (backend-generated)
  /// path formats so that QRs from the payment request confirmation screen work.
  static QrPaymentIntent? fromUri(Uri uri) {
    try {
      // ── zdfi.me URLs ──────────────────────────────────────────────────────
      if (uri.host.toLowerCase() == 'zdfi.me' && uri.pathSegments.isNotEmpty) {
        final segments = uri.pathSegments;
        final firstSegment = segments[0];

        // Strip leading '@' if present (app format); accept bare zendtag too (backend format).
        final zendtag = firstSegment.startsWith('@')
            ? firstSegment.substring(1).toLowerCase()
            : firstSegment.toLowerCase();

        if (zendtag.isEmpty) return null;

        // Request link intent: /{tag}/{request_link_id}
        if (segments.length >= 2 && segments[1].isNotEmpty) {
          return QrPaymentIntent(
            zendtag: zendtag,
            requestLinkId: segments[1],
          );
        }

        // Fixed-amount or open intent: /{tag}?amount=X&note=Y
        final amountParam = uri.queryParameters['amount'];
        final double? amount = _parsePositiveAmount(amountParam);
        final note = uri.queryParameters['note'];

        return QrPaymentIntent(
          zendtag: zendtag,
          amountUsdc: amount,
          note: note?.isNotEmpty == true ? note : null,
        );
      }

      // ── zendapp:// custom scheme ──────────────────────────────────────────
      if (uri.scheme == 'zendapp' && uri.host == 'pay') {
        final zendtag = uri.queryParameters['zendtag'];
        if (zendtag == null || zendtag.isEmpty) return null;

        final amountParam = uri.queryParameters['amount'];
        final double? amount = _parsePositiveAmount(amountParam);
        final note = uri.queryParameters['note'];
        final requestId = uri.queryParameters['request_id'];

        return QrPaymentIntent(
          zendtag: zendtag.toLowerCase(),
          amountUsdc: amount,
          note: note?.isNotEmpty == true ? note : null,
          requestLinkId: requestId?.isNotEmpty == true ? requestId : null,
        );
      }
    } catch (_) {
      // Silently return null for any parse errors
    }

    return null;
  }

  /// Parses an amount string, returning a positive double or null.
  static double? _parsePositiveAmount(String? amountStr) {
    if (amountStr == null || amountStr.isEmpty) return null;
    final parsed = double.tryParse(amountStr);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  /// Builds a fixed-amount `zdfi.me` URL for the given [zendtag] and [amount].
  ///
  /// Example: `buildFixedAmountUrl('alice', 10.5, 'Coffee')` →
  /// `https://zdfi.me/@alice?amount=10.5&note=Coffee`
  static String buildFixedAmountUrl(
    String zendtag,
    double amount,
    String? note,
  ) {
    final params = <String, String>{'amount': amount.toString()};
    if (note != null && note.isNotEmpty) {
      params['note'] = note;
    }
    final uri = Uri(
      scheme: 'https',
      host: 'zdfi.me',
      path: '/@$zendtag',
      queryParameters: params,
    );
    return uri.toString();
  }

  @override
  String toString() =>
      'QrPaymentIntent(zendtag: $zendtag, amountUsdc: $amountUsdc, '
      'note: $note, requestLinkId: $requestLinkId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QrPaymentIntent &&
          runtimeType == other.runtimeType &&
          zendtag == other.zendtag &&
          amountUsdc == other.amountUsdc &&
          note == other.note &&
          requestLinkId == other.requestLinkId;

  @override
  int get hashCode =>
      zendtag.hashCode ^
      amountUsdc.hashCode ^
      note.hashCode ^
      requestLinkId.hashCode;
}
