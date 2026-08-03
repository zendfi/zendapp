import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ConnectedAppsScreen extends StatelessWidget {
  const ConnectedAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(title: 'Connected apps'),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: zt.bgSecondary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PhosphorIconsBold.link,
                          size: 28,
                          color: zt.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No apps connected',
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Third-party apps you authorise will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          fontSize: 13,
                          color: zt.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            icon: Icon(PhosphorIconsBold.caretLeft, color: zt.textPrimary),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700,
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
