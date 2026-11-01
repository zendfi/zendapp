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

  @override
  String get userMessage => errorCopyFor(errorCode, retryable: retryable);

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
