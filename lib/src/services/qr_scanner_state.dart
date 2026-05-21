/// Tracks whether the in-app QR scanner is currently active.
///
/// Used by [app.dart] to suppress duplicate deep links fired by the Android
/// App Links system when [mobile_scanner] decodes a zdfi.me URL — the OS
/// intercepts the URL and fires it as a deep link at the same time as
/// [_onDetect] receives it, which would open two payment sheets.
class QrScannerState {
  QrScannerState._();

  static bool _active = false;

  /// True while [QrScannerScreen] is mounted.
  static bool get isActive => _active;

  static void setActive(bool active) => _active = active;
}
