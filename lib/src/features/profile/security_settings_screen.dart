import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../../services/biometric_service.dart';
import '../../services/cloud_backup_service.dart';
import '../../services/signing_policy_service.dart';
import '../onboarding/national_id_entry_screen.dart';
import '../onboarding/recovery_setup_screen.dart';
import 'change_pin_screen.dart';
import 'export_backup_screen.dart';
import 'recovery_phrase_screen.dart';

/// Settings > Security screen.
///
/// Sections:
/// - Change PIN
/// - Biometric unlock (toggle, hidden on unsupported devices)
/// - Require PIN on every payment (toggle)
/// - Require PIN above amount (toggle + amount input)
/// - Export wallet
///   - Export encrypted backup
///   - View recovery phrase
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _biometric = BiometricService();
  final _policy = SigningPolicyService();

  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _pinPerPaymentEnabled = false;
  bool _pinThresholdEnabled = false;
  double? _pinThresholdAmount;
  bool _loading = true;
  bool _hasRecoveryBackup = false;

  final _thresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final biometricSupported = await _biometric.isAvailable();
    final biometricEnabled =
        biometricSupported ? await _biometric.isEnabled() : false;
    final snapshot = await _policy.snapshot();
    // Check if recovery backup exists (best-effort — don't crash settings if Drive unavailable)
    bool hasRecovery = false;
    try {
      final cloud = CloudBackupService();
      hasRecovery = await cloud.hasRecoveryPacket();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _biometricSupported = biometricSupported;
      _biometricEnabled = biometricEnabled;
      _pinPerPaymentEnabled = snapshot.pinPerPaymentEnabled;
      _pinThresholdEnabled = snapshot.pinThresholdEnabled;
      _pinThresholdAmount = snapshot.pinThresholdAmount;
      _hasRecoveryBackup = hasRecovery;
      if (snapshot.pinThresholdAmount != null) {
        _thresholdController.text =
            snapshot.pinThresholdAmount!.toStringAsFixed(0);
      }
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'To enable biometrics, use the lock screen and tap "Use biometrics" after PIN entry.'),
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      await _biometric.disable();
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric unlock disabled.')),
      );
    }
  }

  Future<void> _togglePinPerPayment(bool value) async {
    await _policy.setPinPerPayment(value);
    if (!mounted) return;
    setState(() => _pinPerPaymentEnabled = value);
  }

  Future<void> _togglePinThreshold(bool value) async {
    if (value) {
      // Enabling — use existing amount if set, otherwise default to 500
      final amount = _pinThresholdAmount ?? 500.0;
      await _policy.setPinThreshold(amount: amount);
      if (!mounted) return;
      setState(() {
        _pinThresholdEnabled = true;
        _pinThresholdAmount = amount;
        _thresholdController.text = amount.toStringAsFixed(0);
      });
    } else {
      await _policy.disablePinThreshold();
      if (!mounted) return;
      setState(() => _pinThresholdEnabled = false);
    }
  }

  Future<void> _saveThresholdAmount(String raw) async {
    final amount = double.tryParse(raw.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    await _policy.setPinThreshold(amount: amount);
    if (!mounted) return;
    setState(() => _pinThresholdAmount = amount);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Back button
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: zt.textPrimary),
                  ),
                  Text(
                    'Security',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 22,
                      color: zt.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(
                child: Center(child: ZendLoader()),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── PIN section ──────────────────────────────────
                      _SectionLabel('PIN', zt),
                      const SizedBox(height: 8),
                      _SettingsGroup(zt: zt, tiles: [
                        _Tile(
                          icon: Icons.pin_outlined,
                          label: 'Change PIN',
                          zt: zt,
                          onTap: () =>
                              pushZendSlide(context, const ChangePinScreen()),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // ── Biometric section ────────────────────────────
                      if (_biometricSupported) ...[
                        _SectionLabel('Biometrics', zt),
                        const SizedBox(height: 8),
                        _SettingsGroup(zt: zt, tiles: [
                          if (_biometricEnabled)
                            _ToggleTile(
                              icon: Icons.fingerprint,
                              label: 'Biometric unlock',
                              subtitle: 'Tap to disable biometric unlock',
                              value: true,
                              zt: zt,
                              onChanged: _toggleBiometric,
                            )
                          else
                            _Tile(
                              icon: Icons.fingerprint,
                              label: 'Biometric unlock',
                              zt: zt,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Lock the app, enter your PIN, then tap "Use biometrics" to enable.',
                                    ),
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                              },
                            ),
                        ]),
                        const SizedBox(height: 20),
                      ],

                      // ── Payments section ─────────────────────────────
                      _SectionLabel('Payments', zt),
                      const SizedBox(height: 8),
                      _SettingsGroup(zt: zt, tiles: [
                        _ToggleTile(
                          icon: Icons.lock_outline,
                          label: 'Require PIN on every payment',
                          subtitle:
                              'Re-enter PIN before every send, regardless of amount',
                          value: _pinPerPaymentEnabled,
                          zt: zt,
                          onChanged: _togglePinPerPayment,
                        ),
                        _ToggleTile(
                          icon: Icons.price_check,
                          label: 'Require PIN above amount',
                          subtitle: _pinThresholdEnabled && _pinThresholdAmount != null
                              ? 'PIN required for sends over \$${_pinThresholdAmount!.toStringAsFixed(0)}'
                              : 'PIN required for sends over a set amount',
                          value: _pinThresholdEnabled,
                          zt: zt,
                          onChanged: _togglePinThreshold,
                        ),
                      ]),

                      // Amount input — only shown when threshold toggle is on
                      if (_pinThresholdEnabled) ...[
                        const SizedBox(height: 12),
                        _AmountInput(
                          controller: _thresholdController,
                          zt: zt,
                          onSaved: _saveThresholdAmount,
                        ),
                      ],

                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _pinPerPaymentEnabled
                              ? 'PIN is required before every send.'
                              : _pinThresholdEnabled && _pinThresholdAmount != null
                                  ? 'Sends below \$${_pinThresholdAmount!.toStringAsFixed(0)} use session signing. PIN required above.'
                                  : 'Sends use session signing after app unlock. No extra PIN needed.',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 12,
                            color: zt.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Recovery section ─────────────────────────────
                      _SectionLabel('PIN Recovery', zt),
                      const SizedBox(height: 8),
                      _SettingsGroup(zt: zt, tiles: [
                        _Tile(
                          icon: _hasRecoveryBackup
                              ? Icons.verified_outlined
                              : Icons.shield_outlined,
                          label: _hasRecoveryBackup
                              ? 'Update recovery backup'
                              : 'Set up PIN recovery',
                          zt: zt,
                          onTap: () {
                            if (_hasRecoveryBackup) {
                              pushZendSlide(context,
                                  const NationalIdEntryScreen());
                            } else {
                              pushZendSlide(
                                  context,
                                  const RecoverySetupScreen(
                                      isFirstTime: false));
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _hasRecoveryBackup
                              ? 'Recovery backup is active. If you forget your PIN, you can recover using your government ID.'
                              : 'Set up recovery so you can regain wallet access if you forget your PIN.',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 12,
                            color: zt.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Export wallet section ────────────────────────
                      _SectionLabel('Export wallet', zt),
                      const SizedBox(height: 8),
                      _SettingsGroup(zt: zt, tiles: [
                        _Tile(
                          icon: Icons.download_outlined,
                          label: 'Export encrypted backup',
                          zt: zt,
                          onTap: () => pushZendSlide(
                              context, const ExportBackupScreen()),
                        ),
                        _Tile(
                          icon: Icons.key_outlined,
                          label: 'View recovery phrase',
                          zt: zt,
                          onTap: () => pushZendSlide(
                              context, const RecoveryPhraseScreen()),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Back up your wallet before switching devices.',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 12,
                            color: zt.textSecondary,
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

// ── Amount input for threshold ─────────────────────────────────────────────

class _AmountInput extends StatelessWidget {
  const _AmountInput({
    required this.controller,
    required this.zt,
    required this.onSaved,
  });

  final TextEditingController controller;
  final ZendTheme zt;
  final void Function(String) onSaved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: zt.border),
      ),
      child: Row(
        children: [
          Text(
            'Require PIN above',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$',
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 16,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 16,
                color: zt.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '500',
                hintStyle: TextStyle(color: zt.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: onSaved,
              onEditingComplete: () => onSaved(controller.text),
            ),
          ),
          TextButton(
            onPressed: () => onSaved(controller.text),
            child: Text(
              'Save',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: zt.accentBright,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared UI components ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.zt);
  final String label;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
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
  const _SettingsGroup({required this.tiles, required this.zt});
  final List<Widget> tiles;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
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

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon,
      required this.label,
      required this.zt,
      required this.onTap});
  final IconData icon;
  final String label;
  final ZendTheme zt;
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

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.zt,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ZendTheme zt;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: zt.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: zt.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: zt.textSecondary,
                  ),
                ),
              ],
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
