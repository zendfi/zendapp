/// Singleton controller that allows code outside the widget tree (e.g. app.dart)
/// to switch the [ZendShell] tab index. [ZendShell]'s state registers itself
/// here on init and clears on dispose.
class ZendShellController {
  ZendShellController._();

  static ZendShellController? _instance;

  /// The current active shell controller, set when ZendShell mounts.
  static ZendShellController? get instance => _instance;

  /// Called by [ZendShell]'s initState to register the tab-switch callback.
  static ZendShellController activate(void Function(int) switchTab) {
    final ctrl = _instance ?? ZendShellController._();
    _instance = ctrl;
    ctrl._switchTab = switchTab;
    return ctrl;
  }

  /// Called by [ZendShell]'s dispose.
  static void deactivate() {
    _instance?._switchTab = null;
    _instance = null;
  }

  void Function(int)? _switchTab;

  /// Switch to the given tab index (0 = Home, 1 = Send, 2 = Activity).
  void switchToTab(int index) => _switchTab?.call(index);
}
