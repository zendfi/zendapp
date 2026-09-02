import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../onboarding/welcome_screen.dart';
import 'account_information_screen.dart';
import 'contact_support_screen.dart';
import 'settings_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// You — ZEND BETA spec §29-30 (LOCKED): "You is deliberately boring.
/// That's a compliment." Avatar + @tag, then exactly three rows —
/// Settings, Help, Log out. Everything else (activity, mutuals, pools)
/// belongs contextually elsewhere per spec §1.1's minimalism principle —
/// this tab does not surface any of them, even as a summary.
///
/// Tapping the avatar/tag opens [AccountInformationScreen] (spec §30 —
/// "edit username, profile photo, identity information" — an identity
/// editor, not a social profile dashboard). Account/security/appearance/
/// privacy controls that used to live directly on this screen now live
/// one tap deeper in [SettingsScreen] — this screen only routes to them.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.showBackButton = true});

  /// Whether to render the back-arrow header.
  ///
  /// Defaults to `true` for the existing pushed-screen usage
  /// (`pushZendSlide(context, const ProfileScreen())`), where a Navigator
  /// route sits underneath and popping is the correct behaviour.
  ///
  /// Pass `false` when this screen is the "You" tab root inside [ZendShell]:
  /// as a bare PageView child it has no route of its own to pop, so the
  /// back arrow would either no-op or (worse) pop the whole shell off the
  /// app's root stack. Tab roots elsewhere (`ActivityScreen`, `DmListScreen`)
  /// follow the same no-back-button convention for the same reason.
  final bool showBackButton;

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
            if (showBackButton)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // ── Identity: avatar + @tag (spec §29 wireframe) ──
                  Center(
                    child: GestureDetector(
                      onTap: () => pushZendSlide(context, const AccountInformationScreen()),
                      child: Column(
                        children: [
                          _AvatarUploadButton(displayName: displayName),
                          const SizedBox(height: 12),
                          Text(
                            zendtag.isNotEmpty ? zendtag : displayName,
                            style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 18, color: zt.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Divider(color: zt.border, height: 1, indent: 20, endIndent: 20),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _TileGroup(tiles: [
                      _Tile(
                        label: 'Settings',
                        onTap: () => pushZendSlide(context, const SettingsScreen()),
                      ),
                      _Tile(
                        label: 'Help',
                        onTap: () => pushZendSlide(context, const ContactSupportScreen()),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _Tile(
                      label: 'Log out',
                      destructive: true,
                      onTap: () => _confirmLogout(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              if (i < tiles.length - 1) Divider(height: 1, thickness: 1, color: zt.border, indent: 16),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Standard nav tile — spec §29's "Settings →" / "Help →" / "Log out →" ──

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap, this.destructive = false});

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final color = destructive ? ZendColors.destructive : zt.textPrimary;
    return Material(
      color: destructive ? ZendColors.destructive.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: destructive ? BorderRadius.circular(ZendRadii.xl) : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: destructive ? BorderRadius.circular(ZendRadii.xl) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: color)),
              ),
              Icon(PhosphorIconsRegular.caretRight, size: 16, color: destructive ? color : zt.textSecondary),
            ],
          ),
        ),
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
                style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 18, color: zt.textPrimary),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                icon: PhosphorIconsRegular.camera,
                label: 'Take photo',
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              _PickerRow(
                icon: PhosphorIconsRegular.imageSquare,
                label: 'Choose from library',
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (hasPhoto)
                _PickerRow(
                  icon: PhosphorIconsRegular.trash,
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
            radius: 32,
            photoUrl: model.currentAvatarUrl,
            initials: widget.displayName.isNotEmpty ? widget.displayName[0].toUpperCase() : null,
          ),
          if (_uploading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                child: const Center(child: ZendLoader(size: 18, strokeWidth: 2, color: Colors.white)),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: ZendColors.accentBright, shape: BoxShape.circle),
                child: const Icon(PhosphorIconsRegular.pencilSimple, size: 10, color: Colors.white),
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
              Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: color)),
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
                decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
              ),
            ),
            Text(
              'Log out?',
              style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 22, color: zt.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              "You'll need to sign in again to access your account.",
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary, height: 1.4),
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
              child: const Text('Cancel', style: TextStyle(fontFamily: 'Geist', fontSize: 15)),
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
