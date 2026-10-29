import 'package:flutter/widgets.dart';

/// Singleton controller that allows code outside the widget tree (e.g. app.dart)
/// to switch the [ZendShell] tab index. [ZendShell]'s state registers itself
/// here on init and clears on dispose.
class ZendShellController {
  ZendShellController._();

  static ZendShellController? _instance;

  /// The current active shell controller, set when ZendShell mounts.
  static ZendShellController? get instance => _instance;

  /// The shell's current tab, or null while no shell is mounted (signed out,
  /// onboarding, splash). Lets UI that lives *outside* the shell — the web
  /// desktop sidebar in `ZendWebFrame` — mirror the selected tab and appear
  /// only once the user is actually inside the app.
  static final ValueNotifier<int?> currentTab = ValueNotifier<int?>(null);

  /// True once the Feed's balance hero has scrolled off screen; the shell
  /// then shows the floating Zend button on Feed too.
  static final ValueNotifier<bool> feedHeroHidden = ValueNotifier(false);

  /// Called by [ZendShell]'s initState to register the tab-switch callback.
  static ZendShellController activate(
    void Function(int) switchTab, {
    int initialTab = 0,
  }) {
    final ctrl = _instance ?? ZendShellController._();
    _instance = ctrl;
    ctrl._switchTab = switchTab;
    // Deferred: activate runs inside ZendShell.initState, i.e. during a build.
    // Setting the notifier there could leave the web frame (an ancestor that
    // already built this pass) on its signed-out layout until a resize forced
    // a rebuild. A post-frame update always lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_instance == ctrl) currentTab.value = initialTab;
    });
    return ctrl;
  }

  /// Called by [ZendShell]'s dispose.
  static void deactivate() {
    _instance?._switchTab = null;
    _instance = null;
    currentTab.value = null;
  }

  /// Called by [ZendShell] whenever its visible tab changes (tap or swipe).
  static void reportTab(int index) {
    if (_instance != null) currentTab.value = index;
  }

  void Function(int)? _switchTab;

  /// Switch to the given tab index (0 = Feed, 1 = People, 2 = Chats, 3 = You).
  /// See ZendShell's own tab-order comment for the source of truth.
  void switchToTab(int index) => _switchTab?.call(index);
}
