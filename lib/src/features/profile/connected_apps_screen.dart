import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class ConnectedAppsScreen extends StatelessWidget {
  const ConnectedAppsScreen({super.key});

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
              _Header(title: 'Connected apps'),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: ZendColors.bgPrimary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ZendColors.border),
                ),
                child: Column(
                  children: const [
                    _AppTile(name: 'Shopify', detail: 'Storefront'),
                    _TileDivider(),
                    _AppTile(name: 'Stripe', detail: 'Payments'),
                    _TileDivider(),
                    _AppTile(name: 'Notion', detail: 'Invoices'),
                  ],
                ),
              ),
              const Spacer(),
              OutlineActionButton(label: 'Connect a new app', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ZendColors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.apps, size: 18, color: ZendColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ZendColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 12,
                    color: ZendColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: ZendColors.textSecondary),
        ],
      ),
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: ZendColors.border);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: ZendColors.textPrimary),
        ),
        const SizedBox(width: 8),
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
        const SizedBox(width: 40),
      ],
    );
  }
}
