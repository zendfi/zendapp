import 'dart:async';

import 'package:flutter/material.dart';

import 'src/core/zend_state.dart';
import 'src/design/zend_theme.dart';
import 'src/features/loading/loading_overlay.dart';
import 'src/features/onboarding/splash_screen.dart';

class ZendApp extends StatelessWidget {
  const ZendApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildZendTheme();
    final model = ZendAppModel();

    return ZendScope(
      notifier: model,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Zend! App',
        theme: theme,
        home: const SplashScreen(),
        localeResolutionCallback: (locale, _) {
          if (locale != null) {
            scheduleMicrotask(() => model.setLocale(locale));
          }
          return locale;
        },
        builder: (context, child) {
          return LoadingOverlay(
            child: child ?? const SizedBox(),
          );
        },
      ),
    );
  }
}