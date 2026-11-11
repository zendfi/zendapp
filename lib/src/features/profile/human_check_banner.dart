import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_features.dart';
import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'human_verification_screen.dart';

/// On your own profile: tells you when your check mark is hidden and takes you to check again.
/// Shows nothing for people who never started, who are verified, or while the feature is off.
class HumanCheckBanner extends StatefulWidget {
  const HumanCheckBanner({super.key});

  @override
  State<HumanCheckBanner> createState() => _HumanCheckBannerState();
}

class _HumanCheckBannerState extends State<HumanCheckBanner> {
  String? _status;

  @override
  void initState() {
    super.initState();
    if (ZendFeatures.humanBadge) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    try {
      final s = await ZendScope.read(
        context,
      ).walletService.apiClient.getHumanVerification();
      if (mounted) setState(() => _status = s['status'] as String?);
    } catch (_) {
      // Decoration only; a failed read just shows nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (!ZendFeatures.humanBadge ||
        (status != 'needs_recheck' &&
            status != 'expired' &&
            status != 'revoked')) {
      return const SizedBox.shrink();
    }
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: zt.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(ZendRadii.xl),
          onTap: () async {
            await pushZendSlide(context, const HumanVerificationScreen());
            if (mounted) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(PhosphorIconsFill.sealCheck, color: zt.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Check again to bring back your badge',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 14,
                  color: zt.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
