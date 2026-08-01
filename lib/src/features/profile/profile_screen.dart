import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';import '../../navigation/zend_routes.dart';
import '../onboarding/welcome_screen.dart';
import 'account_information_screen.dart';
import 'bridge_kyc_screen.dart';
import 'change_pin_screen.dart';
import 'connected_apps_screen.dart';
import 'security_settings_screen.dart';
import 'connected_banks_screen.dart';
import 'contact_support_screen.dart';
import '../request/payment_requests_screen.dart';
import 'package:solar_icons/solar_icons.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final displayName = (model.currentDisplayName?.trim().isNotEmpty ?? false)
        ? model.currentDisplayName!
        : (model.username.isNotEmpty ? model.username : 'Zend User');
    final zendtag = model.username.isNotEmpty ? '@${model.username}' : '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
                  ),
                  Expanded(
                    child: Text(
                      'Profile',
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Identity card ──────────────────────────────────────
                    Material(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.xl),
                      child: InkWell(
                        onTap: () => pushZendSlide(context, const AccountInformationScreen()),
                        borderRadius: BorderRadius.circular(ZendRadii.xl),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _AvatarUploadButton(displayName: displayName),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: TextStyle(
                                        fontFamily: 'Satoshi',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: zt.textPrimary,
                                      ),
                                    ),
                                    if (zendtag.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        zendtag,
                                        style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 12, color: zt.textSecondary),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(SolarIconsBold.altArrowRight,
                                  size: 18, color: zt.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Account ────────────────────────────────────────────
                    _SectionLabel('Account'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _Tile(
                        icon: SolarIconsBold.banknote,
                        label: 'Connected banks',
                        onTap: () => pushZendSlide(context, const ConnectedBanksScreen()),
                      ),
                      _Tile(
                        icon: SolarIconsBold.link,
                        label: 'Connected apps',
                        onTap: () => pushZendSlide(context, const ConnectedAppsScreen()),
                      ),
                      _Tile(
                        icon: SolarIconsBold.bill,
                        label: 'Payment requests',
                        onTap: () => pushZendSlide(context, const PaymentRequestsScreen()),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Drop ───────────────────────────────────────────────
                    _SectionLabel('Drop'),
                    const SizedBox(height: 8),
                    _DropDiscoverabilityTile(),

                    const SizedBox(height: 24),

                    // ── Privacy ───────────────────────────────────────────
                    _SectionLabel('Privacy'),
                    const SizedBox(height: 8),
                    _PresencePrivacyTile(),

                    const SizedBox(height: 24),

                    // ── Appearance ─────────────────────────────────────────
                    _SectionLabel('Appearance'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _ToggleTile(
                        icon: SolarIconsBold.moon,
                        label: 'Dark mode',
                        value: model.isDarkMode,
                        onChanged: (_) => model.toggleDarkMode(),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Activity sharing ───────────────────────────────────
                    _SectionLabel('Activity'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _ToggleTile(
                        icon: SolarIconsBold.bell,
                        label: 'Notify network when I share',
                        value: model.notifyMutualsOnShare,
                        onChanged: (_) => unawaited(model.toggleNotifyMutualsOnShare()),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Security ───────────────────────────────────────────
                    _SectionLabel('Security'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _Tile(
                        icon: SolarIconsBold.shieldCheck,
                        label: 'Security settings',
                        onTap: () => pushZendSlide(context, const SecuritySettingsScreen()),
                      ),
                      _Tile(
                        icon: SolarIconsBold.lockPassword,
                        label: 'Change PIN',
                        onTap: () => pushZendSlide(context, const ChangePinScreen()),
                      ),
                      _Tile(
                        icon: SolarIconsBold.shieldUser,
                        label: 'Identity verification',
                        onTap: () => pushZendSlide(context, const BridgeKycScreen()),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Support ────────────────────────────────────────────
                    _SectionLabel('Support'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _Tile(
                        icon: SolarIconsBold.userSpeak,
                        label: 'Contact support',
                        onTap: () => pushZendSlide(context, const ContactSupportScreen()),
                      ),
                    ]),

                    const SizedBox(height: 32),

                    // ── Log out ────────────────────────────────────────────
                    Material(
                      color: ZendColors.destructive.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(ZendRadii.xl),
                      child: InkWell(
                        onTap: () => _confirmLogout(context),
                        borderRadius: BorderRadius.circular(ZendRadii.xl),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(SolarIconsBold.logout,
                                  size: 18, color: ZendColors.destructive),
                              const SizedBox(width: 8),
                              const Text(
                                'Log out',
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: ZendColors.destructive,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
    // Load from shared prefs as a local cache
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
                  Icon(SolarIconsBold.eyeClosed, size: 20, color: zt.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Online status & last seen',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary),
                    ),
                  ),
                  if (_saving) ZendLoader(size: 16, strokeWidth: 1.5, color: zt.accent),
                ],
              ),
            ),
            for (final option in [
              ('everyone', 'Everyone', 'Anyone you chat with'),
              ('contacts', 'Contacts only', 'People you\'ve transacted with'),
              ('nobody',   'Nobody',   'Appear offline to everyone'),
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
                            Text(option.$2, style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, fontWeight: FontWeight.w600, color: zt.textPrimary)),
                            Text(option.$3, style: TextStyle(fontFamily: 'Satoshi', fontSize: 12, color: zt.textSecondary)),
                          ],
                        ),
                      ),
                      if (_visibility == option.$1)
                        Icon(SolarIconsBold.checkCircle, size: 18, color: zt.accent),
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
        style: TextStyle(
          fontFamily: 'Satoshi',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: zt.textSecondary,
        ),
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
              if (i < tiles.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: zt.border,
                  indent: 48,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Standard nav tile ─────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: zt.textPrimary,
                  ),
                ),
              ),
              Icon(SolarIconsBold.altArrowRight, size: 16, color: zt.textSecondary),
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
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: zt.textPrimary,
              ),
            ),
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

// ── Avatar upload button ──────────────────────────────────────────────────────

class _AvatarUploadButton extends StatefulWidget {
  const _AvatarUploadButton({required this.displayName});
  final String displayName;

  @override
  State<_AvatarUploadButton> createState() => _AvatarUploadButtonState();
}

class _AvatarUploadButtonState extends State<_AvatarUploadButton> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final model = ZendScope.of(context);
    final hasPhoto = model.currentAvatarUrl != null;

    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final zt = ZendTheme.of(ctx);
        final bottomInset = MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
          decoration: BoxDecoration(
            color: zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.xxl),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: zt.border,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
              ),
              Text(
                'Profile photo',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                icon: SolarIconsBold.camera,
                label: 'Take photo',
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              _PickerRow(
                icon: SolarIconsBold.galleryAdd,
                label: 'Choose from library',
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (hasPhoto)
                _PickerRow(
                  icon: SolarIconsBold.trashBinMinimalistic,
                  label: 'Remove photo',
                  onTap: () => Navigator.pop(ctx, 'remove'),
                  destructive: true,
                ),
            ],
          ),
        );
      },
    );

    if (choice == null || !mounted) return;

    if (choice == 'remove') {
      setState(() => _uploading = true);
      try {
        final oldUrl = model.currentAvatarUrl;
        await model.walletService.apiClient.deleteAvatar();
        if (oldUrl != null) await CachedNetworkImage.evictFromCache(oldUrl);
        model.setAvatarUrl(null);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove photo')),
          );
        }
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }

    final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final oldUrl = model.currentAvatarUrl;
      final url = await model.walletService.apiClient.uploadAvatar(File(picked.path));
      if (oldUrl != null) await CachedNetworkImage.evictFromCache(oldUrl);
      model.setAvatarUrl(url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload photo')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    return GestureDetector(
      onTap: _uploading ? null : _pickAndUpload,
      child: Stack(
        children: [
          ZendAvatar(
            radius: 28,
            photoUrl: model.currentAvatarUrl,
            initials: widget.displayName.isNotEmpty
                ? widget.displayName[0].toUpperCase()
                : null,
          ),
          if (_uploading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x66000000),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: ZendLoader(size: 18, strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: ZendColors.accentBright,
                  shape: BoxShape.circle,
                ),
                child: const Icon(SolarIconsBold.pen2, size: 9, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Photo picker row ──────────────────────────────────────────────────────────

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final color = destructive ? ZendColors.destructive : zt.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Logout confirmation (bottom sheet, not AlertDialog) ───────────────────────

Future<void> _confirmLogout(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final zt = ZendTheme.of(ctx);
      final bottomInset = MediaQuery.of(ctx).viewPadding.bottom;
      return Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.xxl),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: zt.border,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
            ),
            Text(
              'Log out?',
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "You'll need to sign in again to access your account.",
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontSize: 14,
                color: zt.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Log out',
              backgroundColor: ZendColors.destructive,
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: zt.textSecondary),
              child: const Text(
                'Cancel',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 15),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final model = ZendScope.of(context);
  await model.dropDiscoverabilityService.pause();
  // Unregister this device's FCM token before tearing down the session —
  // otherwise the backend keeps this token associated with the account
  // being signed out of, and a signed-out device kept receiving that
  // account's push notifications until FCM eventually reported the token
  // as stale on some unrelated future send.
  await model.pushNotificationService.unregisterToken();
  try {
    await model.authService.logout();
    model.resetState();
  } catch (_) {
    model.resetState();
  }
  if (!context.mounted) return;
  pushAndRemoveUntilZendSlide(context, const WelcomeScreen(), rootNavigator: true);
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
                  // ── Toggle row ──────────────────────────────────────────
                  Row(
                    children: [
                      // Live indicator dot
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOn
                              ? zt.accentBright
                              : zt.textSecondary.withValues(alpha: 0.35),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        SolarIconsBold.bluetoothWave,
                        size: 20,
                        color: isOn ? zt.accentBright : zt.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Be Discoverable',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: zt.textPrimary,
                          ),
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

                  // ── Description ─────────────────────────────────────────
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 17),
                    child: Text(
                      isOn
                          ? 'Broadcasting a secure Bluetooth signal. Nearby Zend users can send you money via Drop automatically.'
                          : 'Let nearby Zend users send you money via Drop — no sharing your zendtag needed.',
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        fontSize: 12,
                        color: zt.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),

                  // ── "Broadcasting as" label ─────────────────────────────
                  if (isOn && service.currentPayload != null) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 17),
                      child: Row(
                        children: [
                          Icon(SolarIconsBold.recordCircle,
                              size: 10, color: zt.accentBright),
                          const SizedBox(width: 4),
                          Text(
                            'Broadcasting as @${service.currentPayload!.zendtag}',
                            style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: zt.accentBright),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Error banner ────────────────────────────────────────
                  if (!isOn && !isLoading && service.lastError != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 17),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: ZendColors.destructive.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(ZendRadii.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(SolarIconsBold.infoCircle,
                                size: 14, color: ZendColors.destructive),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                service.lastError!,
                                style: const TextStyle(
                                  fontFamily: 'Satoshi',
                                  fontSize: 11,
                                  color: ZendColors.destructive,
                                  height: 1.4,
                                ),
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
