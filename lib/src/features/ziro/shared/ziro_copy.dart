/// Every string Ziro shows (design.md §12), in one place. Follows the
/// workspace rule `user-facing-language`.
library;

import '../../../models/api_exceptions.dart';

abstract final class ZiroCopy {
  static const failed = "That didn't go through. Try again.";
  static const holdPalm = 'Hold your palm up to the screen';
  static const handsLength = "About a hand's length away";
  static const holdStill = 'Hold still';
  static const checking = "Checking it's you";
  static const notFound = "We couldn't find you";
  static const tryAgain = 'Try again';
  static const payAnotherWay = 'Pay another way';
  static const notEnough = 'Not enough in your Zend for this.';
  static const paused = 'Palm pay is paused. Turn it back on in your Zend app.';
  static const paid = 'Paid';
  static const nextCustomer = 'Next customer';
  static const notYou = 'Not you? Cancel';
  static const safetyStop =
      "We stopped this because something didn't look right. Your money hasn't moved.";
  static const duplicatePalm =
      'This palm is already set up for palm pay on another Zend account.';
  static const phoneOnly = 'This works in the Zend app on your phone.';
  static const brightness =
      'Turn your screen brightness all the way up so palms read well.';

  static String charge(String amount) => 'Charge $amount';
  static String hi(String firstName) => 'Hi $firstName';
  static String enterPin(String amount, String merchant) =>
      'Enter your Ziro PIN to pay $amount to $merchant';
  static String zirofee(String amount) => 'Ziro fee $amount';
  static String pinWrong(int left) => left == 1
      ? "That PIN didn't match. 1 try left."
      : "That PIN didn't match. $left tries left.";
}

/// Plain copy for a guide code from the palm camera (contracts §6).
String ziroGuideCopy(String code) => switch (code) {
  'show_palm' => ZiroCopy.holdPalm,
  'move_closer' => 'Move your hand a little closer',
  'move_back' => 'Move your hand a little further away',
  'too_dark' => 'Find a bit more light',
  'too_bright' => 'Move out of the bright light',
  'hold_still' => ZiroCopy.holdStill,
  'other_hand' => 'Now show your other hand',
  'ok' => 'Got it',
  _ => ZiroCopy.holdPalm,
};

/// Plain copy for a camera error event (contracts §6).
String ziroCameraErrorCopy(String code) => switch (code) {
  'camera_denied' => 'Zend needs the camera to read palms. Allow it in Settings.',
  'timeout' => "We couldn't read a palm in time. Try again.",
  _ => ZiroCopy.failed,
};

/// Copy for a `refused` result. The enclave's own `message` wins when it
/// sends one; these cover an empty message.
String ziroRefusedCopy(String code, String message) {
  if (message.trim().isNotEmpty) return message.trim();
  return switch (code) {
    'INSUFFICIENT' => ZiroCopy.notEnough,
    'PAUSED' => ZiroCopy.paused,
    'LIMIT' => 'This is over the limit set for palm pay.',
    'EXPIRED' => 'That took too long. Try again.',
    _ => ZiroCopy.failed,
  };
}

/// A refusal or failure with its words already chosen for people.
class ZiroException implements Exception {
  const ZiroException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// Thrown when the phone refused to sign or send what it was given.
class ZiroSafetyStop extends ZiroException {
  const ZiroSafetyStop([this.reason = '']) : super(ZiroCopy.safetyStop);

  /// For logs and tests; never shown.
  final String reason;
}

/// Words for any error a Ziro screen catches. Core and the enclave write
/// their `message` for people (contracts §0), so it is shown when present.
String ziroErrorText(Object e) {
  if (e is ZiroException) return e.message;
  if (e is ApiException) {
    if (e.statusCode < 500 && e.rawMessage.trim().isNotEmpty) {
      return e.rawMessage.trim();
    }
    return e.statusCode >= 500 ? ZiroCopy.failed : e.userMessage;
  }
  if (e is ZendException) return e.userMessage;
  return ZiroCopy.failed;
}
