import '../models/notification_destination.dart';

/// Stores a pending [NotificationDestination] when a push notification tap
/// arrives while the app is locked or unauthenticated. The destination is
/// consumed once the user authenticates or unlocks the app.
///
/// Mirrors [PendingDeepLinkService]'s static-field pattern — no persistence
/// needed since the user must re-tap if the process is killed before unlock.
class PendingNotificationService {
  PendingNotificationService._();

  static NotificationDestination? _pending;

  static void store(NotificationDestination destination) =>
      _pending = destination;

  static NotificationDestination? consume() {
    final dest = _pending;
    _pending = null;
    return dest;
  }

  static bool get hasPending => _pending != null;
}
