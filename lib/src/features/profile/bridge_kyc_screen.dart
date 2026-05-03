import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class BridgeKycScreen extends StatefulWidget {
  const BridgeKycScreen({super.key});

  @override
  State<BridgeKycScreen> createState() => _BridgeKycScreenState();
}

class _BridgeKycScreenState extends State<BridgeKycScreen> {
  bool _loading = true;
  bool _starting = false;
  String? _error;

  bool _isApproved = false;
  String? _kycStatus;
  String? _tosStatus;
  String? _kycLink;
  String? _lastCheckedAt;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      final data = await model.walletService.apiClient.getBridgeKycStatus();
      _applyStatus(data);
    } catch (e) {
      setState(() {
        _error = 'Failed to load verification status';
        _loading = false;
      });
    }
  }

  Future<void> _startKyc() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      final data = await model.walletService.apiClient.startBridgeKyc();
      _applyStatus(data);
      final link = data['kyc_link'] as String?;
      if (link != null && link.isNotEmpty) {
        await _openKycLink(link);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to start verification. Please try again.';
        _starting = false;
      });
    }
  }

  void _applyStatus(Map<String, dynamic> data) {
    setState(() {
      _isApproved = data['is_approved'] as bool? ?? false;
      _kycStatus = data['kyc_status'] as String?;
      _tosStatus = data['tos_status'] as String?;
      _kycLink = (data['kyc_link'] ?? data['latest_kyc_link']) as String?;
      _lastCheckedAt = data['last_checked_at'] as String?;
      _loading = false;
      _starting = false;
    });
  }

  Future<void> _openKycLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open verification link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header — matches AccountInformationScreen pattern
              _ScreenHeader(
                title: 'Identity verification',
                trailing: _loading
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.refresh,
                            color: ZendColors.textSecondary, size: 20),
                        onPressed: _loadStatus,
                      ),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Expanded(child: Center(child: ZendLoader()))
              else
                Expanded(
                  child: ZendScrollPage(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Status card
                        _StatusCard(
                          isApproved: _isApproved,
                          kycStatus: _kycStatus,
                          tosStatus: _tosStatus,
                          lastCheckedAt: _lastCheckedAt,
                        ),
                        const SizedBox(height: 20),

                        // What this unlocks
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ZendColors.bgSecondary,
                            borderRadius:
                                BorderRadius.circular(ZendRadii.xxl),
                          ),
                          child: const _InfoSection(),
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: ZendColors.destructive
                                  .withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(ZendRadii.lg),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                color: ZendColors.destructive,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (_isApproved) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: ZendColors.positive
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(ZendRadii.xl),
                              border: Border.all(
                                color: ZendColors.positive
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.verified_user,
                                    color: ZendColors.positive, size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Your identity is verified. Local payment rails are enabled.',
                                    style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 14,
                                      color: ZendColors.positive,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          PrimaryButton(
                            label: _starting
                                ? 'Starting verification...'
                                : _kycLink != null
                                    ? 'Continue verification'
                                    : 'Start verification',
                            onPressed: _starting
                                ? () {}
                                : _kycLink != null
                                    ? () => _openKycLink(_kycLink!)
                                    : _startKyc,
                          ),
                          const SizedBox(height: 12),
                          if (_kycLink != null)
                            TextButton(
                              onPressed: _startKyc,
                              child: const Text(
                                'Get a new verification link',
                                style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 13,
                                  color: ZendColors.textSecondary,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Text(
                            'Verification is powered by Bridge. Your data is encrypted and never shared without your consent.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 12,
                              color: ZendColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: ZendColors.textPrimary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ZendColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: trailing,
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isApproved,
    required this.kycStatus,
    required this.tosStatus,
    required this.lastCheckedAt,
  });

  final bool isApproved;
  final String? kycStatus;
  final String? tosStatus;
  final String? lastCheckedAt;

  @override
  Widget build(BuildContext context) {
    final statusColor = isApproved ? ZendColors.positive : ZendColors.accent;
    final statusLabel = isApproved
        ? 'Verified'
        : kycStatus == null
            ? 'Not started'
            : _humanize(kycStatus!);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ZendColors.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.md),
                ),
                child: Icon(
                  isApproved
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verification status',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (tosStatus != null) ...[
            const SizedBox(height: 14),
            const Divider(color: ZendColors.border, height: 1),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Terms of service',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: ZendColors.textSecondary,
                  ),
                ),
                Text(
                  _humanize(tosStatus!),
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ZendColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
          if (lastCheckedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last checked: ${_formatDate(lastCheckedAt!)}',
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: ZendColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _humanize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return iso;
    }
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What verification unlocks',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: ZendColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in [
          ('🇺🇸', 'US ACH bank transfers'),
          ('🇬🇧', 'UK Faster Payments'),
          ('🇪🇺', 'EU SEPA transfers'),
          ('🇲🇽', 'Mexico SPEI'),
          ('🇨🇴', 'Colombia BRE-B'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(item.$1, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Text(
                  item.$2,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: ZendColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          'Nigerian bank transfers (NGN) work without verification.',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 12,
            color: ZendColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
