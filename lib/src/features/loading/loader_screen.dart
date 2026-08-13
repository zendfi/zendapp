import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class LoaderScreen extends StatelessWidget {
  const LoaderScreen({
    super.key,
    this.message = 'Loading',
  });

  final String message;

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
                // The spinner is the main event here — sized up from the
                // usual inline 22px so it reads as the focal point of the
                // screen, with the status message legible underneath it
                // rather than competing with a logo above.
                const ZendLoader(size: 40, strokeWidth: 3),
                const SizedBox(height: 20),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'CircularStd',
                    fontSize: 14,
                    color: ZendColors.textOnDeep,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
