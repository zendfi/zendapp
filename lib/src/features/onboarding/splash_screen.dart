import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(ZendMotion.splash, () {
      if (!mounted) return;
      pushReplacementZendSlide(context, const WelcomeScreen());
    });
  }

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
