import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../onboarding/welcome_screen.dart';
import 'account_information_screen.dart';
import 'bridge_kyc_screen.dart';
import 'change_pin_screen.dart';
import 'connected_apps_screen.dart';
import 'connected_banks_screen.dart';
import 'contact_support_screen.dart';
import 'customise_page_screen.dart';
import '../request/payment_requests_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final displayName = (model.currentDisplayName?.trim().isNotEmpty ?? false)
        ? model.currentDisplayName!
        : (model.username.isNotEmpty ? model.username : 'Zend User');
    final linkHandle = model.username.isNotEmpty ? '@${model.username}' : 'user';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Back button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF0F0F0) : ZendColors.textPrimary),
                  ),
                ],
              ),
            ),

            // ── User card ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: ZendColors.bgDeep,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _AvatarUploadButton(
                      displayName: displayName,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ZendColors.textOnDeep,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'zdfi.me/$linkHandle',
                            style: const TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 12,
                              color: Color(0x80F0F0F0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => pushZendSlide(context, const AccountInformationScreen()),
                      style: TextButton.styleFrom(
                        foregroundColor: ZendColors.accentPop,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text(
                        'Edit',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Scrollable settings ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('Account'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      tiles: [
                        _ProfileTile(
                          icon: Icons.person_outline,
                          label: 'Account information',
                          onTap: () => pushZendSlide(context, const AccountInformationScreen()),
                        ),
                        _ProfileTile(
                          icon: Icons.account_balance_outlined,
                          label: 'Connected banks',
                          onTap: () => pushZendSlide(context, const ConnectedBanksScreen()),
                        ),
                        _ProfileTile(
                          icon: Icons.link,
                          label: 'Connected apps',
                          onTap: () => pushZendSlide(context, const ConnectedAppsScreen()),
                        ),
                        _ProfileTile(
                          icon: Icons.palette_outlined,
                          label: 'Customise payment page',
                          onTap: () => pushZendSlide(context, const CustomisePageScreen()),
                        ),
                        _ProfileTile(
                          icon: Icons.receipt_long_outlined,
                          label: 'Payment requests',
                          onTap: () => pushZendSlide(context, const PaymentRequestsScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('Appearance'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      tiles: [
                        _ProfileToggleTile(
                          icon: Icons.dark_mode_outlined,
                          label: 'Dark mode',
                          value: model.isDarkMode,
                          onChanged: (_) => model.toggleDarkMode(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('Security'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      tiles: [
                        _ProfileTile(
                          icon: Icons.pin_outlined,
                          label: 'Change PIN',
                          onTap: () => pushZendSlide(context, const ChangePinScreen()),
                        ),
                        _ProfileTile(
                          icon: Icons.verified_user_outlined,
                          label: 'Identity verification',
                          onTap: () => pushZendSlide(context, const BridgeKycScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('Support'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      tiles: [
                        _ProfileTile(
                          icon: Icons.support_agent,
                          label: 'Contact support',
                          onTap: () => pushZendSlide(context, const ContactSupportScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: () => _confirmLogout(context),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: ZendColors.destructive.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(ZendRadii.lg),
                          border: Border.all(color: ZendColors.destructive.withValues(alpha: 0.18)),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.logout, size: 18, color: ZendColors.destructive),
                            SizedBox(width: 8),
                            Text(
                              'Log out',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ZendColors.destructive,
                              ),
                            ),
                          ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: zt.textSecondary,
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i < tiles.length - 1) {
        children.add(Divider(height: 1, color: zt.border));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: zt.border),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
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
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: zt.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: zt.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ProfileToggleTile extends StatelessWidget {
  const _ProfileToggleTile({
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
                fontFamily: 'DMSans',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: zt.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: ZendColors.accentBright,
            activeTrackColor: ZendColors.accentBright.withValues(alpha: 0.4),
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final zt = ZendTheme.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: zt.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: zt.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              _SheetOption(
                icon: Icons.camera_alt_outlined,
                label: 'Take photo',
                onTap: () => Navigator.pop(ctx, 'camera'),
                zt: zt,
              ),
              _SheetOption(
                icon: Icons.photo_library_outlined,
                label: 'Choose from library',
                onTap: () => Navigator.pop(ctx, 'gallery'),
                zt: zt,
              ),
              if (hasPhoto)
                _SheetOption(
                  icon: Icons.delete_outline,
                  label: 'Remove photo',
                  onTap: () => Navigator.pop(ctx, 'remove'),
                  zt: zt,
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
        await model.walletService.apiClient.deleteAvatar();
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

    final source =
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final url = await model.walletService.apiClient.uploadAvatar(File(picked.path));
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
            initials: widget.displayName.isNotEmpty
                ? widget.displayName[0].toUpperCase()
                : null,
            backgroundColor: const Color(0x332D6A4F),
          ),
          if (_uploading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x66000000),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: ZendColors.accentBright,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.zt,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ZendTheme zt;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? ZendColors.destructive : zt.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      );
    },
  );

  if (shouldLogout != true) return;
  if (!context.mounted) return;

  final model = ZendScope.of(context);

  try {
    await model.authService.logout();
    model.resetState();
  } catch (_) {
    // Best-effort logout — still navigate away
    model.resetState();
  }

  if (!context.mounted) return;
  pushAndRemoveUntilZendSlide(context, const WelcomeScreen(), rootNavigator: true);
}


