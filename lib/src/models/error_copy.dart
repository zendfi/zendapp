/// User-facing copy for backend error codes.
///
/// One table for every flow (send, request, add cash, bank send, sign-in),
/// so a code the backend already explains never reaches the user as
/// "Something went wrong". Rules for entries:
///   * say what happened in plain words, then what to do next;
///   * never blame the user for our or the network's failure;
///   * no internal words (rail, gasless, coin object, RPC, nonce).
///
/// Codes not listed fall back by family (see [errorCopyFor]) before the
/// generic line, so a new backend code still gets a sensible message.
library;

const _copy = <String, String>{
  // ── Balance ──────────────────────────────────────────────────────────
  'INSUFFICIENT_BALANCE':
      "You don't have enough in your balance for this. "
      'Add money or send a smaller amount.',
  'SUI_ADDRESS_BALANCE_INSUFFICIENT':
      "You don't have enough in your balance "
      'for this. Add money or send a smaller amount.',
  'SUI_NO_COIN_OBJECTS':
      "You don't have enough in your balance for this. "
      'Add money or send a smaller amount.',
  'SUI_GASLESS_MINIMUM': "That amount is too small to send. Try a bit more.",
  'SUI_BALANCE_UNAVAILABLE':
      "We couldn't check your balance just now. Try again in a moment.",
  'SUI_BALANCE_INVALID':
      "We couldn't check your balance just now. Try again in a moment.",
  'USDC_BALANCE_FETCH_FAILED':
      "We couldn't check your balance just now. Try again in a moment.",

  // ── Amount ───────────────────────────────────────────────────────────
  'INVALID_AMOUNT': r'Enter an amount between $0.01 and $10,000.',
  'TRANSFER_RATE_LIMITED':
      "You've sent a lot in a short time. Wait a few minutes and try again.",
  'VIBE_DAILY_LIMIT_EXCEEDED':
      "You've hit today's \$25 Vibe limit. Try again tomorrow.",

  'AMOUNT_TOO_SMALL':
      'That amount is below the minimum for this bank. '
      r'Withdraw at least $0.50 to a Naira account, or $5 elsewhere.',

  'ZENDTAG_CHANGE_LIMIT': "You've used both of your Zend tag changes.",
  'ZENDTAG_CHANGE_TOO_SOON': 'You can change your Zend tag once a year.',
  'ZENDTAG_UNCHANGED': 'That is already your Zend tag.',
  'INVALID_DETAILS': 'Check the details and try again.',

  // ── Recipient ────────────────────────────────────────────────────────
  'RECIPIENT_NOT_FOUND':
      "We couldn't find anyone with that Zend tag. Check the spelling.",
  'SELF_TRANSFER': "You can't send money to yourself.",
  'CROSS_RAIL_RECIPIENT':
      "This person can't receive yet. Ask them to open Zend and finish "
      'setting up.',
  'RECIPIENT_WALLET_NOT_REGISTERED':
      "This person can't receive yet. Ask them to open Zend and finish "
      'setting up.',
  'BLOCKED_RECIPIENT': "You can't send money to this account.",
  'USER_BLOCKED': "You can't interact with this account.",
  'RECIPIENT_SCREEN_FAILED':
      "We couldn't verify this recipient right now. Try again shortly.",

  // ── Your account ─────────────────────────────────────────────────────
  'SENDER_RAIL_WALLET_MISSING':
      'Your Zend is still being set up. Sign out and back in, then try '
      'again.',
  'SUI_WALLET_NOT_REGISTERED':
      'Your Zend is still being set up. Sign out and back in, then try '
      'again.',
  'WALLET_NOT_REGISTERED':
      'Your Zend is still being set up. Sign out and back in, then try '
      'again.',
  'WALLET_MISMATCH':
      "This device doesn't match your account. Sign out and back in.",
  'STEP_UP_REQUIRED':
      'For a payment this size we need to confirm it is you. Sign in with '
      'Google again when asked.',
  'STEP_UP_CHECK_FAILED':
      "We couldn't confirm it's you. Try again, and use the same Google "
      'account.',
  'SUI_COHORT_REQUIRED': 'Sending is not available on your account yet.',
  'RAIL_NOT_SUPPORTED': 'Sending is not available on your account yet.',
  'P2P_POLICY_DISABLED':
      'Sending is paused for a moment while we do maintenance. Try again soon.',

  // ── Add cash ─────────────────────────────────────────────────────────
  'RATES_UNAVAILABLE':
      "We couldn't get today's exchange rate. Try again in a minute.",
  'ORDER_CREATE_FAILED':
      "We couldn't start that top-up. Nothing was charged. Try again.",
  'OTP_TIMEOUT': 'That took too long. Start the top-up again.',

  // ── Sign-in / OTP ────────────────────────────────────────────────────
  'OTP_RATE_LIMITED': 'Please wait a moment before requesting another code.',
  'INVALID_PHONE_FORMAT': 'Please enter a valid phone number.',
  'INVALID_OTP_CODE': "That code doesn't match. Please try again.",
  'OTP_EXPIRED': 'Your code has expired. Please request a new one.',
  'OTP_MAX_ATTEMPTS': 'Too many attempts. Please request a new code.',
  'PHONE_ALREADY_REGISTERED':
      'This phone number is already registered. Try signing in.',
  'ZENDTAG_UNAVAILABLE': 'That username is taken. Please choose another.',
  'BACKUP_NOT_FOUND': 'No backup found. Setting things up fresh.',
  'NONCE_ALREADY_USED': 'Beacon expired. Scanning for a fresh connection…',
  'NONCE_SUPERSEDED': 'Beacon expired. Scanning for a fresh connection…',
  'INVALID_NONCE': 'Beacon expired. Scanning for a fresh connection…',

  // ── Pools ────────────────────────────────────────────────────────────
  'POOL_NOT_ACTIVE': 'This pool is no longer active.',
  'POOL_FULL': 'This pool has already reached its goal.',

  // ── Generic transport ────────────────────────────────────────────────
  'UNEXPECTED_RESPONSE':
      "We're having trouble reaching Zend. Try again in a moment.",
};

const _networkBusy =
    'The network is busy right now. Nothing was sent. Try again in a moment.';
const _ourSide =
    "Something on our side didn't work. Nothing was sent. Try again.";
const generic = "That didn't go through. Try again.";

/// Copy for [code], falling back by family so unknown codes still read well.
/// [retryable] (from the backend body) picks the network-busy line for
/// transient failures.
String errorCopyFor(String code, {bool? retryable}) {
  final exact = _copy[code];
  if (exact != null) return exact;
  // Chain providers, sponsor gas station, epoch/gas reads: transient.
  if (code.startsWith('SUI_PROVIDER') ||
      code.startsWith('SUI_GAS_STATION') ||
      code.endsWith('_UNAVAILABLE') ||
      code == 'SUBMISSION_FAILED' ||
      code == 'RPC_ERROR' ||
      code == 'BLOCKHASH_FETCH_FAILED' ||
      retryable == true) {
    return _networkBusy;
  }
  // Envelope, serialization and record failures: our bug, not the user's.
  if (code.startsWith('INVALID_') ||
      code.startsWith('MISSING_') ||
      code.endsWith('_FAILED') ||
      code.endsWith('_INVALID') ||
      code == 'INTERNAL_ERROR' ||
      code == 'DB_ERROR') {
    return _ourSide;
  }
  return generic;
}
