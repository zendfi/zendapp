import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class ContactSupportScreen extends StatelessWidget {
  const ContactSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: 'Contact support'),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: zt.bgCard,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'We respond in under 2 hours.',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    _SupportRow(icon: Icons.email_outlined, label: 'support@zendfi.com'),
                    const SizedBox(height: 10),
                    _SupportRow(icon: Icons.chat_bubble_outline, label: 'Live chat'),
                    const SizedBox(height: 10),
                    _SupportRow(icon: Icons.article_outlined, label: 'Help center'),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(label: 'Start chat', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: zt.textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back, color: zt.textPrimary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}
