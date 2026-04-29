import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class LoaderScreen extends StatelessWidget {
  const LoaderScreen({
    super.key,
    this.message = 'Loading',
    this.showLogo = true,
  });

  final String message;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLogo)
                  Column(
                    children: [
                      Image.asset(
                        'assets/logo/Zend.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: ZendColors.textOnDeep,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 14),
                const ZendLoader(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
