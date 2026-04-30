import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';

/// Pure visual splash screen. Navigation is handled by the session-restore
/// wrapper in app.dart.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'zendapp',
                style: TextStyle(
                  color: ZendColors.textOnDeep,
                  fontSize: 28,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '· by ZendFi',
                style: TextStyle(
                  color: Color(0x66E8F4EC),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
