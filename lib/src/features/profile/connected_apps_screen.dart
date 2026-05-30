import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';

class ConnectedAppsScreen extends StatelessWidget {
  const ConnectedAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: 'Connected apps'),
              const SizedBox(height: 18),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.apps_outlined,
                        size: 48,
                        color: zt.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No apps connected yet',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Third-party apps you authorise will\nappear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: zt.textSecondary,
                        ),
                      ),
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
