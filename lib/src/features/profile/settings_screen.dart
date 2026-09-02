import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'bridge_kyc_screen.dart';
import 'change_pin_screen.dart';
import 'connected_apps_screen.dart';
import 'connected_banks_screen.dart';
import 'security_settings_screen.dart';
import '../request/payment_requests_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Settings — reached from You (spec §29: "Settings →"). Everything that
/// was previously mixed into the You tab's own body lives here instead —
/// spec §1.1's minimalism principle ("no redundant... section") means the
/// tab root itself stays down to identity + three rows, and all the actual
/// account/security/appearance controls move one tap deeper.
///
/// No "Support"/"Contact support" section here — that's the You tab's own
/// top-level "Help" row (spec §29), and duplicating the same destination
/// under Settings too would be exactly the redundancy §1.1 warns against.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                  ),
                  Expanded(
                    child: Text(
                      'Settings',
                      style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 24, color: zt.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('Account'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _Tile(
                        icon: PhosphorIconsRegular.bank,
                        label: 'Connected banks',
                        onTap: () => pushZendSlide(context, const ConnectedBanksScreen()),
                      ),
                      _Tile(
                        icon: PhosphorIconsRegular.link,
                        label: 'Connected apps',
                        onTap: () => pushZendSlide(context, const ConnectedAppsScreen()),
                      ),
                      _Tile(
                        icon: PhosphorIconsRegular.receipt,
                        label: 'Payment requests',
                        onTap: () => pushZendSlide(context, const PaymentRequestsScreen()),
                      ),
                    ]),

                    const SizedBox(height: 24),
                    _SectionLabel('Drop'),
                    const SizedBox(height: 8),
                    const _DropDiscoverabilityTile(),

                    const SizedBox(height: 24),
                    _SectionLabel('Privacy'),
                    const SizedBox(height: 8),
                    const _PresencePrivacyTile(),

                    const SizedBox(height: 24),
                    _SectionLabel('Appearance'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _ToggleTile(
                        icon: PhosphorIconsRegular.moon,
                        label: 'Dark mode',
                        value: model.isDarkMode,
                        onChanged: (_) => model.toggleDarkMode(),
                      ),
                    ]),

                    const SizedBox(height: 24),
                    _SectionLabel('Activity'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _ToggleTile(
                        icon: PhosphorIconsRegular.bell,
                        label: 'Notify network when I share',
                        value: model.notifyMutualsOnShare,
                        onChanged: (_) => unawaited(model.toggleNotifyMutualsOnShare()),
                      ),
                    ]),

                    const SizedBox(height: 24),
                    _SectionLabel('Security'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _Tile(
                        icon: PhosphorIconsRegular.shieldCheck,
                        label: 'Security settings',
                        onTap: () => pushZendSlide(context, const SecuritySettingsScreen()),
                      ),
                      // Hidden for zkLogin accounts: they have no PIN, so
                      // this would open a flow with nothing to change.
                      if (!model.isZkLoginAccount)
                        _Tile(
                          icon: PhosphorIconsRegular.lockSimple,
                          label: 'Change PIN',
                          onTap: () => pushZendSlide(context, const ChangePinScreen()),
                        ),
                      _Tile(
                        icon: PhosphorIconsRegular.identificationBadge,
                        label: 'Identity verification',
                        onTap: () => pushZendSlide(context, const BridgeKycScreen()),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Presence privacy tile ────────────────────────────────────────────────────

class _PresencePrivacyTile extends StatefulWidget {
  const _PresencePrivacyTile();

  @override
  State<_PresencePrivacyTile> createState() => _PresencePrivacyTileState();
}

class _PresencePrivacyTileState extends State<_PresencePrivacyTile> {
  String _visibility = 'everyone';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _visibility = prefs.getString('presence_visibility') ?? 'everyone');
      }
    });
  }

  Future<void> _update(String newVal) async {
    if (_saving || newVal == _visibility) return;
    setState(() => _saving = true);
    try {
      await ZendScope.of(context).dmService.updatePresencePrivacy(newVal);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('presence_visibility', newVal);
      if (mounted) setState(() => _visibility = newVal);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update — try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: ColoredBox(
        color: zt.bgSecondary,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.eyeClosed, size: 20, color: zt.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Online status & last seen',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary),
                    ),
                  ),
                  if (_saving) ZendLoader(size: 16, strokeWidth: 1.5, color: zt.accent),
                ],
              ),
            ),
            for (final option in [
              ('everyone', 'Everyone', 'Anyone you chat with'),
              ('contacts', 'Contacts only', 'People you\'ve transacted with'),
              ('nobody', 'Nobody', 'Appear offline to everyone'),
            ]) ...[
              Divider(color: zt.border, height: 1, indent: 48, endIndent: 0),
              InkWell(
                onTap: () => _update(option.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(option.$2, style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontWeight: FontWeight.w600, color: zt.textPrimary)),
                            Text(option.$3, style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary)),
                          ],
                        ),
                      ),
                      if (_visibility == option.$1)
                        Icon(PhosphorIconsRegular.checkCircle, size: 18, color: zt.accent),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
      ),
    );
  }
}

// ── Tile group (card with dividers, no border) ────────────────────────────────

class _TileGroup extends StatelessWidget {
  const _TileGroup({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: ColoredBox(
        color: zt.bgSecondary,
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1) Divider(height: 1, thickness: 1, color: zt.border, indent: 48),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Standard nav tile ─────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: zt.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary)),
              ),
              Icon(PhosphorIconsRegular.caretRight, size: 16, color: zt.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Toggle tile ───────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: zt.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary)),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: zt.accentBright,
            activeTrackColor: zt.accentBright.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

// ── Drop Discoverability Tile ─────────────────────────────────────────────────

class _DropDiscoverabilityTile extends StatelessWidget {
  const _DropDiscoverabilityTile();

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final service = model.dropDiscoverabilityService;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final zt = ZendTheme.of(context);
        final isOn = service.isDiscoverable;
        final isLoading = service.isLoading;

        return ClipRRect(
          borderRadius: BorderRadius.circular(ZendRadii.xl),
          child: ColoredBox(
            color: zt.bgSecondary,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOn ? zt.accentBright : zt.textSecondary.withValues(alpha: 0.35),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(PhosphorIconsRegular.bluetoothConnected, size: 20, color: isOn ? zt.accentBright : zt.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Be Discoverable',
                          style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary),
                        ),
                      ),
                      if (isLoading)
                        ZendLoader(size: 20, strokeWidth: 2, color: zt.accentBright)
                      else
                        Switch.adaptive(
                          value: isOn,
                          onChanged: (_) => service.toggle(),
                          activeThumbColor: zt.accentBright,
                          activeTrackColor: zt.accentBright.withValues(alpha: 0.4),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 17),
                    child: Text(
                      isOn
                          ? 'Broadcasting a secure Bluetooth signal. Nearby Zend users can send you money via Drop automatically.'
                          : 'Let nearby Zend users send you money via Drop — no sharing your zendtag needed.',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary, height: 1.4),
                    ),
                  ),
                  if (isOn && service.currentPayload != null) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 17),
                      child: Row(
                        children: [
                          Icon(PhosphorIconsRegular.record, size: 10, color: zt.accentBright),
                          const SizedBox(width: 4),
                          Text(
                            'Broadcasting as @${service.currentPayload!.zendtag}',
                            style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: zt.accentBright),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!isOn && !isLoading && service.lastError != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 17),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: ZendColors.destructive.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(ZendRadii.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(PhosphorIconsRegular.warningCircle, size: 14, color: ZendColors.destructive),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                service.lastError!,
                                style: const TextStyle(fontFamily: 'Geist', fontSize: 11, color: ZendColors.destructive, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
