import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../onboarding/welcome_screen.dart';
import 'account_information_screen.dart';
import 'change_password_screen.dart';
import 'connected_apps_screen.dart';
import 'connected_banks_screen.dart';
import 'contact_support_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);

    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
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
                    icon: const Icon(Icons.arrow_back, color: ZendColors.textPrimary),
                  ),
                ],
              ),
            ),

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
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Color(0x332D6A4F),
                      child: Icon(Icons.person, color: ZendColors.textOnDeep, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Blessed Oyinbo',
                            style: TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ZendColors.textOnDeep,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'zdfi.me/@${model.username}',
                            style: const TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 12,
                              color: Color(0x80E8F4EC),
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

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                          onTap: () {
                            // TODO: Navigate to payment page customisation screen
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('Security'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      tiles: [
                        _ProfileTile(
                          icon: Icons.lock_outline,
                          label: 'Change password',
                          onTap: () => pushZendSlide(context, const ChangePasswordScreen()),
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
                    const Spacer(),
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
                    const SizedBox(height: 24),
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
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: ZendColors.textSecondary,
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i < tiles.length - 1) {
        children.add(const Divider(height: 1, color: ZendColors.border));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: ZendColors.bgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZendColors.border),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ZendColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: ZendColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: ZendColors.textSecondary),
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
  pushAndRemoveUntilZendSlide(context, const WelcomeScreen(), rootNavigator: true);
}
