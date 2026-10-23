import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/zend_state.dart';
import '../features/shell/zend_entry_sheet.dart';
import '../navigation/zend_shell_controller.dart';
import 'zend_tokens.dart';

/// Which web layout the app is currently rendered in. Read by screens that
/// need to adapt (today only [ZendShell], which drops its bottom bar and FAB
/// when the desktop sidebar is showing them instead).
class ZendWebLayout extends InheritedWidget {
  const ZendWebLayout({super.key, required this.desktop, required super.child});

  /// True when the desktop sidebar is visible outside the app column.
  final bool desktop;

  static bool isDesktop(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZendWebLayout>()?.desktop ??
      false;

  @override
  bool updateShouldNotify(ZendWebLayout oldWidget) =>
      oldWidget.desktop != desktop;
}

/// Hosts the whole app on the web.
///
/// The web app is the *same* app as mobile, presented as a miniature: every
/// screen, sheet and route renders inside one phone-width column, so nothing
/// built for a phone ever gets stretched across a monitor. Three modes:
///
///  * **Mobile** (< [tabletBreakpoint]) — full bleed, identical to the app.
///  * **Tablet** — the column is centred on a quiet backdrop.
///  * **Desktop** (>= [desktopBreakpoint]) — the column plus a sidebar on the
///    left (tabs + the Zend action) and a "get the app" panel on the right.
///
/// Because this wraps the Navigator (it is used from `MaterialApp.builder`),
/// bottom sheets and dialogs are constrained to the column automatically.
/// It also rewrites [MediaQuery] size to the column's, so width-derived logic
/// downstream (text scaling, layout breakpoints) sees a phone, not a monitor.
///
/// On non-web platforms this is a pass-through.
class ZendWebFrame extends StatelessWidget {
  const ZendWebFrame({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Below this width the app runs full-bleed, exactly like the phone app.
  static const double tabletBreakpoint = 600;

  static const double _maxColumnHeight = 920;
  static const double _minColumnWidth =
      375; // iPhone SE / the app's design frame
  static const double _maxColumnWidth = 460;
  static const double _minPanelWidth = 200;
  static const double _maxPanelWidth = 280;
  static const double _gap = 40;
  static const double _outerMargin = 32;

  /// Column width follows the window *height* at a modern phone's aspect
  /// ratio (~9:19.5), so a tall monitor gets a roomier column and a laptop a
  /// tighter one, instead of one fixed width that is wrong for both.
  static double columnWidthFor(double columnHeight) =>
      (columnHeight * 0.48).clamp(_minColumnWidth, _maxColumnWidth);

  /// Desktop mode turns on as soon as both side panels fit at their minimum
  /// width beside the column. Derived, not a magic number, so it moves with
  /// the column.
  static bool isDesktopWidth(double windowWidth, double columnWidth) =>
      windowWidth >= columnWidth + 2 * (_minPanelWidth + _gap + _outerMargin);

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    final size = MediaQuery.sizeOf(context);
    if (size.width < tabletBreakpoint) {
      return ZendWebLayout(desktop: false, child: child);
    }

    final zt = ZendTheme.of(context);
    // Leave breathing room top and bottom, but never let a short window
    // squash the column below a usable height.
    final verticalMargin = size.height > 720 ? 24.0 : 0.0;
    final columnHeight = (size.height - verticalMargin * 2).clamp(
      0.0,
      _maxColumnHeight,
    );
    final columnWidth = columnWidthFor(columnHeight);
    final desktop = isDesktopWidth(size.width, columnWidth);
    // Side panels take whatever room is left, within limits.
    final panelWidth = ((size.width - columnWidth) / 2 - _gap - _outerMargin)
        .clamp(_minPanelWidth, _maxPanelWidth);

    // Tablet: no sidebar, so the shell keeps its own bottom bar and FAB.
    final column = _AppColumn(
      width: columnWidth,
      height: columnHeight,
      rounded: verticalMargin > 0,
      child: ZendWebLayout(desktop: false, child: child),
    );

    // Material gives the side panels default text styling (without it Flutter
    // draws its yellow "missing Material" underline); SizedBox.expand makes
    // the backdrop fill the whole window.
    return Material(
      color: zt.bgSecondary,
      child: SizedBox.expand(
        child: desktop
            ? ValueListenableBuilder<int?>(
                valueListenable: ZendShellController.currentTab,
                builder: (context, tab, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: panelWidth,
                      child: tab == null
                          ? const _BrandPanel()
                          : _Sidebar(
                              navigatorKey: navigatorKey,
                              currentTab: tab,
                            ),
                    ),
                    const SizedBox(width: _gap),
                    // Rebuilt with the tab notifier so ZendWebLayout.desktop
                    // flips the moment the shell mounts or unmounts: before
                    // sign-in there is no sidebar, so nothing is hidden.
                    _AppColumn(
                      width: columnWidth,
                      height: columnHeight,
                      rounded: verticalMargin > 0,
                      child: ZendWebLayout(desktop: tab != null, child: child),
                    ),
                    const SizedBox(width: _gap),
                    SizedBox(width: panelWidth, child: const _GetTheAppPanel()),
                  ],
                ),
              )
            : Center(child: column),
      ),
    );
  }
}

/// The phone-sized viewport the real app renders into.
class _AppColumn extends StatelessWidget {
  const _AppColumn({
    required this.width,
    required this.height,
    required this.rounded,
    required this.child,
  });

  final double width;
  final double height;
  final bool rounded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = BorderRadius.circular(rounded ? 28 : 0);
    final media = MediaQuery.of(context);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: radius,
        border: Border.all(color: zt.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 40,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: MediaQuery(
          // The app inside should believe it is on a phone of this size.
          // Browser chrome has no notches or system bars, so padding is zero.
          data: media.copyWith(
            size: Size(width, height),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Desktop navigation: the four shell tabs plus the Zend action, mirrored
/// from [ZendShell] through [ZendShellController].
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.navigatorKey, required this.currentTab});

  final GlobalKey<NavigatorState> navigatorKey;
  final int currentTab;

  /// Returns to the shell (closing any pushed screen or open sheet) and then
  /// switches tab — the same effect as tapping the bottom bar on mobile.
  void _goToTab(int index) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ZendShellController.instance?.switchToTab(index);
  }

  void _openZend() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    showZendEntrySheet(navigator.context);
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Wordmark(),
        const SizedBox(height: 32),
        _NavItem(
          icon: PhosphorIconsRegular.houseLine,
          activeIcon: PhosphorIconsFill.houseLine,
          label: 'Feed',
          active: currentTab == 0,
          badge: model.activityUnreadCount,
          onTap: () => _goToTab(0),
        ),
        _NavItem(
          icon: PhosphorIconsRegular.usersThree,
          activeIcon: PhosphorIconsFill.usersThree,
          label: 'People',
          active: currentTab == 1,
          onTap: () => _goToTab(1),
        ),
        _NavItem(
          icon: PhosphorIconsRegular.chatCircleText,
          activeIcon: PhosphorIconsFill.chatCircleText,
          label: 'Chats',
          active: currentTab == 2,
          badge: model.dmUnreadTotal,
          onTap: () => _goToTab(2),
        ),
        _NavItem(
          icon: PhosphorIconsRegular.userCircle,
          activeIcon: PhosphorIconsFill.userCircle,
          label: 'You',
          active: currentTab == 3,
          onTap: () => _goToTab(3),
        ),
        const SizedBox(height: 24),
        // The app's one verb, same dark-pill treatment as the mobile FAB.
        Semantics(
          button: true,
          label: 'Zend money',
          child: Material(
            color: ZendColors.bgDeep,
            borderRadius: BorderRadius.circular(ZendRadii.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              onTap: _openZend,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        ZendColors.accentPop,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/icons/zend-icon-navbar.png',
                        width: 18,
                        height: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Zend',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ZendColors.accentPop,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final color = active ? zt.textPrimary : zt.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: active ? zt.bgCard : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(active ? activeIcon : icon, color: color, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  if (badge > 0 && !active)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ZendColors.destructive,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        'Zend!',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: zt.textPrimary,
        ),
      ),
    );
  }
}

/// Left panel before sign-in, where there are no tabs to show yet.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Wordmark(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            'Send money to your people, right from your browser.',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 15,
              height: 1.4,
              color: zt.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Right panel: the web app is the miniature, the phone app is the full
/// thing (Drop, push, biometrics…), so point people at it.
class _GetTheAppPanel extends StatelessWidget {
  const _GetTheAppPanel();

  static const _downloadUrl = 'https://usezend.app';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: zt.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: zt.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get the app',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Notifications, Drop and more live in the Zend! app. '
                'Scan to download.',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  height: 1.4,
                  color: zt.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Semantics(
                  label: 'QR code linking to usezend.app',
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: _downloadUrl,
                      size: 140,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
