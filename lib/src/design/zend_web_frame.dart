import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/zend_state.dart';
import '../features/shell/zend_entry_sheet.dart';
import '../navigation/zend_shell_controller.dart';
import 'zend_tokens.dart';

/// Which web layout the app is rendered in.
class ZendWebLayout extends InheritedWidget {
  const ZendWebLayout({
    super.key,
    required this.desktop,
    required this.wide,
    required super.child,
  });

  /// True when the desktop sidebar is showing (signed in, wide window).
  /// [ZendShell] then drops its bottom bar/FAB and goes two-pane.
  final bool desktop;

  /// True on any wide web window, signed in or not. Sheets open as dialogs.
  final bool wide;

  static bool isDesktop(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZendWebLayout>()?.desktop ??
      false;

  static bool isWide(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ZendWebLayout>()?.wide ?? false;

  @override
  bool updateShouldNotify(ZendWebLayout old) =>
      old.desktop != desktop || old.wide != wide;
}

/// Hosts the app on the web.
///
///  * **Narrow** (< [desktopBreakpoint]) — full bleed, identical to the phone.
///  * **Wide, signed out** — onboarding as a centred card on a plain page.
///  * **Wide, signed in** — a real desktop layout: full-height sidebar on the
///    left, the app filling the rest of the window (ZendShell goes two-pane).
///
/// Pass-through off web.
class ZendWebFrame extends StatelessWidget {
  const ZendWebFrame({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  static const double desktopBreakpoint = 900;
  static const double sidebarWidth = 240;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    final size = MediaQuery.sizeOf(context);
    if (size.width < desktopBreakpoint) {
      return ZendWebLayout(desktop: false, wide: false, child: child);
    }

    final zt = ZendTheme.of(context);
    final media = MediaQuery.of(context);
    final flat = media.copyWith(
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
    );

    return Material(
      color: zt.bgSecondary,
      child: ValueListenableBuilder<int?>(
        valueListenable: ZendShellController.currentTab,
        builder: (context, tab, _) {
          if (tab == null) {
            return _SignedOutPage(
              media: flat,
              child: ZendWebLayout(desktop: false, wide: true, child: child),
            );
          }
          final contentWidth = size.width - sidebarWidth - 1;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyN): () =>
                  _Sidebar.openZend(navigatorKey),
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: _Sidebar(navigatorKey: navigatorKey, currentTab: tab),
                ),
                Container(width: 1, color: zt.border),
                Expanded(
                  child: MediaQuery(
                    data: flat.copyWith(size: Size(contentWidth, size.height)),
                    child: ColoredBox(
                      color: zt.bgPrimary,
                      child: ZendWebLayout(
                        desktop: true,
                        wide: true,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Sign-in / onboarding on a wide window: the phone onboarding screens in a
/// card, with the wordmark above and a quiet "get the app" link below.
class _SignedOutPage extends StatelessWidget {
  const _SignedOutPage({required this.media, required this.child});

  final MediaQueryData media;
  final Widget child;

  static const double _cardWidth = 440;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final cardHeight = (media.size.height - 160).clamp(480.0, 720.0);

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Wordmark(),
            const SizedBox(height: 20),
            Container(
              width: _cardWidth,
              height: cardHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: zt.bgPrimary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: zt.border),
              ),
              child: MediaQuery(
                data: media.copyWith(size: Size(_cardWidth, cardHeight)),
                child: child,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://usezend.app')),
              child: Text(
                'Get the Zend! app for your phone',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-height desktop navigation, mirrored from [ZendShell] through
/// [ZendShellController].
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.navigatorKey, required this.currentTab});

  final GlobalKey<NavigatorState> navigatorKey;
  final int currentTab;

  void _goToTab(int index) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ZendShellController.instance?.switchToTab(index);
  }

  static void openZend(GlobalKey<NavigatorState> navigatorKey) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    showZendEntrySheet(navigator.context);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final tag = model.currentZendtag;
    final name = model.currentDisplayName ?? tag ?? '';
    final avatar = model.currentAvatarUrl;

    return ColoredBox(
      color: zt.bgSecondary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Wordmark(),
            const SizedBox(height: 28),
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
            const SizedBox(height: 20),
            Tooltip(
              message: 'Zend money (N)',
              child: Material(
                color: ZendColors.bgDeep,
                borderRadius: BorderRadius.circular(ZendRadii.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => openZend(navigatorKey),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
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
            const Spacer(),
            // "You" lives at the bottom as the account row, desktop-style.
            Material(
              color: currentTab == 3 ? zt.bgCard : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _goToTab(3),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: zt.bgCard,
                        backgroundImage: (avatar != null && avatar.isNotEmpty)
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: (avatar == null || avatar.isEmpty)
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(color: zt.textPrimary),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: zt.textPrimary,
                              ),
                            ),
                            if (tag != null)
                              Text(
                                '@$tag',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 12,
                                  color: zt.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        PhosphorIconsRegular.gearSix,
                        size: 18,
                        color: zt.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: active ? zt.bgCard : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            mouseCursor: SystemMouseCursors.click,
            hoverColor: zt.bgCard.withValues(alpha: 0.6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(active ? activeIcon : icon, color: color, size: 21),
                  const SizedBox(width: 12),
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
      padding: const EdgeInsets.only(left: 12),
      child: Text(
        'Zend!',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: zt.textPrimary,
        ),
      ),
    );
  }
}
