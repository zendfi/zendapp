import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'national_id_entry_screen.dart';

/// Shown after onboarding and accessible from Settings → Security.
///
/// Explains the recovery system in plain terms and lets the user:
/// - Continue → [NationalIdEntryScreen] to create the recovery packet
/// - Skip → navigate to home (or pop back to settings)
class RecoverySetupScreen extends StatelessWidget {
  const RecoverySetupScreen({
    super.key,
    this.onComplete,
    this.isFirstTime = true,
  });

  /// Called when recovery setup is complete. If null, pops the navigator.
  final VoidCallback? onComplete;

  /// True when called from onboarding (shows "Set it up later" instead of back).
  final bool isFirstTime;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back / close
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(
                      isFirstTime ? Icons.close : Icons.arrow_back,
                      color: zt.textPrimary,
                    ),
                    onPressed: () => _skip(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Icon
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: zt.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 36,
                    color: zt.accent,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Set up wallet recovery',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'If you ever forget your PIN, you can recover your wallet using your government ID number — completely without involving Zend.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  height: 1.5,
                  color: zt.textSecondary,
                ),
              ),
              const SizedBox(height: 28),

              // Benefits list
              _BulletItem(
                icon: Icons.cloud_outlined,
                text: 'Your recovery file is saved to your Google Drive or iCloud — Zend never sees it.',
                zt: zt,
              ),
              const SizedBox(height: 12),
              _BulletItem(
                icon: Icons.fingerprint,
                text: 'Your government ID number is the only key — we can\'t decrypt it for you.',
                zt: zt,
              ),
              const SizedBox(height: 12),
              _BulletItem(
                icon: Icons.lock_outline,
                text: 'Even if your phone is lost, your money stays recoverable.',
                zt: zt,
              ),

              const Spacer(),

              // Consequence of skipping
              if (isFirstTime)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'If you skip this, a forgotten PIN means you permanently lose access to your wallet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: zt.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),

              PrimaryButton(
                label: 'Set up recovery',
                onPressed: () => _proceed(context),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _skip(context),
                child: Text(
                  isFirstTime ? 'Set it up later' : 'Cancel',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: zt.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _proceed(BuildContext context) {
    pushZendSlide(
      context,
      NationalIdEntryScreen(onComplete: onComplete),
    );
  }

  void _skip(BuildContext context) {
    if (onComplete != null) {
      onComplete!();
    } else {
      Navigator.of(context).pop();
    }
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({
    required this.icon,
    required this.text,
    required this.zt,
  });

  final IconData icon;
  final String text;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: zt.accentBright),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              height: 1.45,
              color: zt.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
