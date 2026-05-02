import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

/// Bridge KYC screen — lets users start or resume identity verification
/// required for local payment rails (US ACH, UK Faster Payments, EU SEPA, etc.)
class BridgeKycScreen extends StatefulWidget {
  const BridgeKycScreen({super.key});

  @override
  State<BridgeKycScreen> createState() => _BridgeKycScreenState();
}

class _BridgeKycScreenState extends State<BridgeKycScreen> {
  bool _loading = true;
  bool _starting = false;
  String? _error;

  // KYC status fields
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
      // Open the KYC link in the browser
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
      appBar: AppBar(
        backgroundColor: ZendColors.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ZendColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Identity verification',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ZendColors.textPrimary,
          ),
        ),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh, color: ZendColors.textSecondary),
              onPressed: _loadStatus,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: ZendLoader())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
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
                  const SizedBox(height: 24),

                  // What this unlocks
                  const _InfoSection(),
                  const SizedBox(height: 24),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ZendColors.destructive.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(ZendRadii.lg),
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
                    // Already approved
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ZendColors.positive.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(ZendRadii.xl),
                        border: Border.all(
                          color: ZendColors.positive.withValues(alpha: 0.3),
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
                    // CTA
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
                ],
              ),
            ),
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
        color: ZendColors.bgDeep,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isApproved
                    ? Icons.verified_user
                    : Icons.shield_outlined,
                color: statusColor,
                size: 28,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verification status',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: Color(0x80E8F4EC),
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
            const SizedBox(height: 12),
            const Divider(color: Color(0x26E8F4EC), height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Terms of service',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: Color(0x80E8F4EC),
                  ),
                ),
                Text(
                  _humanize(tosStatus!),
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ZendColors.textOnDeep,
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
                color: Color(0x66E8F4EC),
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ZendColors.textPrimary,
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
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(item.$1, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
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
