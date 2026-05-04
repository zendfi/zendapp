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
  });

  @override
  String get userMessage => _mapErrorCodeToMessage(errorCode);

  static String _mapErrorCodeToMessage(String errorCode) {
    switch (errorCode) {
      case 'OTP_RATE_LIMITED':
        return 'Please wait a moment before requesting another code.';
      case 'INVALID_PHONE_FORMAT':
        return 'Please enter a valid phone number.';
      case 'INVALID_OTP_CODE':
        return "That code doesn't match. Please try again.";
      case 'OTP_EXPIRED':
        return 'Your code has expired. Please request a new one.';
      case 'OTP_MAX_ATTEMPTS':
        return 'Too many attempts. Please request a new code.';
      case 'PHONE_ALREADY_REGISTERED':
        return 'This phone number is already registered. Try signing in.';
      case 'ZENDTAG_UNAVAILABLE':
        return 'That username is taken. Please choose another.';
      case 'INSUFFICIENT_BALANCE':
        return "You don't have enough balance for this transfer.";
      case 'RECIPIENT_NOT_FOUND':
        return "We couldn't find that username. Please check and try again.";
      case 'INVALID_AMOUNT':
        return r'Please enter a valid amount between $0.01 and $10,000.';
      case 'TRANSFER_RATE_LIMITED':
        return "You've sent too many transfers recently. Please wait and try again.";
      case 'BACKUP_NOT_FOUND':
        return 'No wallet backup found. Setting up a new wallet.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() =>
      'ApiException($statusCode, $errorCode): $rawMessage';
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
