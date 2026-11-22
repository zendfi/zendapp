import 'dart:async';

/// Something happened to one of your money links while the app was open:
/// collected, taken back after it expired, or paid. Fed from foreground
/// pushes (`zlink_claimed`, `zlink_returned`, `zlink_paid`,
/// `zlink_bank_paid`) so My Links can refresh and stamp the row as it
/// happens.
abstract final class LinkEvents {
  static final _changed = StreamController<String>.broadcast();

  /// Ids of links whose status just changed.
  static Stream<String> get changed => _changed.stream;

  static const _types = {
    'zlink_claimed',
    'zlink_returned',
    'zlink_paid',
    'zlink_bank_paid',
  };

  /// Forwards a push payload if it's about a link.
  static void fromPush(Map<String, dynamic> data) {
    final id = data['link_id'];
    if (_types.contains(data['type']) && id is String && id.isNotEmpty) {
      _changed.add(id);
    }
  }
}
