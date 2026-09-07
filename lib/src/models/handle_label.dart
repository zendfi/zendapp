/// Formatting for a user's handle as it is shown to people.
///
/// A Zend handle is normally a username and reads with a leading `@`. But a
/// zkLogin account that has never chosen a username carries its **email address**
/// as a placeholder handle, and `@someone@gmail.com` reads as a typo rather than
/// as an identity.
///
/// Every display site used to inline `'@$zendtag'`, so each one had to remember
/// this distinction independently — and none of them did.
library;

/// The handle as it should be displayed: `@username`, or a bare email address.
///
/// Detects an email by the presence of `@` rather than by validating the address.
/// The question here is only "does this already read as an address", and a handle
/// containing `@` never wants another one prepended regardless of whether the rest
/// of it parses.
String handleLabel(String? handle) {
  final trimmed = handle?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  return trimmed.contains('@') ? trimmed : '@$trimmed';
}
