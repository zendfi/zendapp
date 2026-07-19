import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import 'package:solar_icons/solar_icons.dart';

class AccountInformationScreen extends StatelessWidget {
  const AccountInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final displayName = (model.currentDisplayName?.trim().isNotEmpty ?? false)
        ? model.currentDisplayName!
        : (model.username.isNotEmpty ? model.username : 'Zend User');
    final zendtag = model.username.isNotEmpty ? '@${model.username}' : '—';
    final paymentLink = model.username.isNotEmpty ? 'zdfi.me/@${model.username}' : '—';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(title: 'Account information'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('Your details'),
                    const SizedBox(height: 8),
                    _InfoGroup(rows: [
                      _InfoRow(label: 'Full name', value: displayName),
                      _InfoRow(label: 'Zendtag', value: zendtag),
                      _InfoRow(label: 'Payment link', value: paymentLink),
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('Contact'),
                    const SizedBox(height: 8),
                    _InfoGroup(rows: [
                      _InfoRow(
                        label: 'Email',
                        value: model.currentUserId != null ? 'On file' : 'Not set',
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

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.rows});
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: ColoredBox(
        color: zt.bgSecondary,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                Divider(height: 1, thickness: 1, color: zt.border, indent: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
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
          Text(
            value,
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared header used by all profile sub-screens ─────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 24,
                color: zt.textPrimary,
              ),
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}
