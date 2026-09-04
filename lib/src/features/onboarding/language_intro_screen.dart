import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'welcome_screen.dart';

/// Key persisted so this screen only shows once per install — a returning
/// user (logged out and back, or a fresh session after sign-out) lands
/// straight on [WelcomeScreen] instead of replaying the intro every time.
const _kLanguageIntroSeenKey = 'language_intro_seen';

/// The very first screen a new install sees: "Hello"/"Welcome" — and its
/// equivalents in a handful of other languages — fading through in turn,
/// center-aligned, with "tap to continue" pinned at the bottom. This is
/// Zend's "borderless" identity stated before a single word of product UI
/// appears (redesign.md §72: "Zend is borderless. The visual system must
/// be prepared for that from day one.") — not itself part of the locked
/// screen spec, so styled independently rather than reusing send/request
/// copy conventions.
///
/// Deliberately not localizing the REST of the app here — this is a fixed,
/// curated set of greetings for atmosphere, not a language picker or an
/// i18n mechanism. flutter_localizations isn't a dependency of this app;
/// this screen hardcodes its own small greeting list rather than pulling
/// in a full localization pipeline for a few seconds of splash content.
class LanguageIntroScreen extends StatefulWidget {
  const LanguageIntroScreen({super.key});

  /// Returns true if this screen should be shown (i.e. hasn't been seen
  /// yet on this install). Call before pushing [WelcomeScreen] directly
  /// from a cold-launch path — see app.dart's session-restore flow.
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kLanguageIntroSeenKey) ?? false);
  }

  @override
  State<LanguageIntroScreen> createState() => _LanguageIntroScreenState();
}

class _Greeting {
  const _Greeting(this.text, this.language);
  final String text;
  final String language;
}

// A curated spread, not exhaustive — spec direction was "as many as we can
// work with, but not too much". Ordered so English opens and closes the
// cycle, bookending the non-Latin scripts in between.
const _greetings = [
  _Greeting('Hello', 'English'),
  _Greeting('Bawo', 'Yorùbá'),
  _Greeting('こんにちは', '日本語'),
  _Greeting('Hola', 'Español'),
  _Greeting('Bonjour', 'Français'),
  _Greeting('你好', '中文'),
  _Greeting('مرحبا', 'العربية'),
  _Greeting('Hallo', 'Deutsch'),
  _Greeting('Ciao', 'Italiano'),
  _Greeting('Olá', 'Português'),
  _Greeting('Привет', 'Русский'),
  _Greeting('नमस्ते', 'हिन्दी'),
  _Greeting('안녕하세요', '한국어'),
  _Greeting('Jambo', 'Kiswahili'),
  _Greeting('Sannu', 'Hausa'),
];

class _LanguageIntroScreenState extends State<LanguageIntroScreen> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    // Slower, more deliberate cadence — enough time to actually read each
    // greeting before it fades to the next one.
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _greetings.length);
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _continue() async {
    _timer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLanguageIntroSeenKey, true);
    if (!mounted) return;
    pushReplacementZendSlide(context, const WelcomeScreen());
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _greetings[_index];
    // Follows the app's own light/dark theme (via ZendTheme, which reads
    // Theme.of(context).brightness — resolved from system brightness by
    // default, same as every other pre-auth screen) instead of a fixed
    // brand-green surface.
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: GestureDetector(
        onTap: _continue,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          // `stretch` is the fix for the "drifting" left edge: with the
          // default `center` cross-axis alignment, the Padding below sizes
          // itself to its child's natural (language-dependent) width, and
          // the outer Column then centers that variable-width box on
          // screen — so the greeting's left edge visibly shifts left/right
          // every time a shorter or longer word swaps in. Stretching the
          // Column instead makes the Padding always span the full screen
          // width, so `Alignment.centerLeft` below has a fixed reference
          // frame and the text's left edge never moves.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                  child: Column(
                    key: ValueKey(_index),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting.text,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        greeting.language,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: zt.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Center(
                  child: Text(
                    'Tap to Continue',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      color: zt.textSecondary.withValues(alpha: 0.7),
                      letterSpacing: 0.3,
                    ),
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
