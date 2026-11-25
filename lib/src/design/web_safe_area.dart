/// The device's safe-area insets as the browser reports them.
///
/// Flutter web never reads `env(safe-area-inset-*)`, so on an iPhone the
/// app's `MediaQuery.padding` is always zero and every `SafeArea` does
/// nothing: in the home-screen app the tab bar sat on the home indicator.
/// [ZendWebFrame] reads the real insets here and hands them to the app.
///
/// The browser only reports them once the viewport has `viewport-fit=cover`,
/// which web/zend_boot_theme.js adds to the viewport tag Flutter installs.
library;

export 'web_safe_area_stub.dart'
    if (dart.library.js_interop) 'web_safe_area_web.dart';
