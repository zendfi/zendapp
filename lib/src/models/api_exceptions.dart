import 'error_copy.dart';

abstract class ZendException implements Exception {
  String get userMessage;

  @override
  String toString() => userMessage;
}

class ApiException extends ZendException {
  final int statusCode;
  final String errorCode;
  final String rawMessage;

  ApiException({
    required this.statusCode,
    required this.errorCode,
    required this.rawMessage,
    this.retryable,
  });

  /// The backend's `retryable` flag, when the body carried one.
  final bool? retryable;

  /// Refusals whose server message is already written for people and says
  /// something specific (a limit, a count). Showing generic copy instead hid
  /// the reason, e.g. that a link was over the most a link can hold.
  static const _serverWorded = {
    'ABOVE_LINK_MAXIMUM',
    'BELOW_MINIMUM',
    'ABOVE_MAXIMUM',
    'LINKS_AT_CAPACITY',
    'DAILY_LINK_LIMIT',
    'LINKS_PILOT_ONLY',
    'ZLINKS_DISABLED',
    'MEMO_TOO_LONG',
    'OWN_LINK',
    'LINK_NOT_FOUND',
  };

  @override
  String get userMessage =>
      _serverWorded.contains(errorCode) && rawMessage.trim().isNotEmpty
      ? rawMessage
      : errorCopyFor(errorCode, retryable: retryable);

  @override
  String toString() => 'ApiException($statusCode, $errorCode): $rawMessage';
}

class NetworkException extends ZendException {
  @override
  String get userMessage =>
      'No internet connection. Check your network and try again.';

  @override
  String toString() => 'NetworkException: $userMessage';
}

class RequestTimeoutException extends ZendException {
  @override
  String get userMessage => 'Request timed out. Please try again.';

  @override
  String toString() => 'RequestTimeoutException: $userMessage';
}

class PinDecryptionException extends ZendException {
  @override
  String get userMessage => 'Incorrect PIN. Please try again.';

  @override
  String toString() => 'PinDecryptionException: $userMessage';
}

/// Friendly text for any error a flow can catch: our exceptions carry their
/// own copy; everything else gets the safe generic line (the raw error is for
/// logs, never the screen).
String friendlyError(Object error) =>
    error is ZendException ? error.userMessage : generic;
