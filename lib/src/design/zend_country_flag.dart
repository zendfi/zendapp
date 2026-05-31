import 'package:flutter/material.dart';

import 'zend_tokens.dart';

/// ISO 3166-1 alpha-2 country codes supported by the local PNG assets.
/// Add entries here as new flags are added to assets/countries/flags/.
enum ZendCountry {
  ng,  // Nigeria
  us,  // United States
  gb,  // United Kingdom
  eu,  // European Union (not ISO but used for SEPA)
  mx,  // Mexico
  co,  // Colombia
}

extension ZendCountryExt on ZendCountry {
  String get assetPath => switch (this) {
        ZendCountry.ng => 'assets/countries/flags/nigeria.png',
        ZendCountry.us => 'assets/countries/flags/usa.png',
        ZendCountry.gb => 'assets/countries/flags/uk.png',
        ZendCountry.eu => 'assets/countries/flags/eu.png',
        ZendCountry.mx => 'assets/countries/flags/mexico.png',
        ZendCountry.co => 'assets/countries/flags/columbia.png',
      };

  String get initials => switch (this) {
        ZendCountry.ng => 'NG',
        ZendCountry.us => 'US',
        ZendCountry.gb => 'GB',
        ZendCountry.eu => 'EU',
        ZendCountry.mx => 'MX',
        ZendCountry.co => 'CO',
      };

  Color get fallbackColor => switch (this) {
        ZendCountry.ng => const Color(0xFF008751),
        ZendCountry.us => const Color(0xFF3C3B6E),
        ZendCountry.gb => const Color(0xFF012169),
        ZendCountry.eu => const Color(0xFF003399),
        ZendCountry.mx => const Color(0xFF006847),
        ZendCountry.co => const Color(0xFFFCD116),
      };
}

/// A circular country flag widget.
///
/// Uses the PNG asset from assets/countries/flags/ and falls back
/// to a colored initials badge if the image fails to load.
class ZendCountryFlag extends StatelessWidget {
  const ZendCountryFlag({
    super.key,
    required this.country,
    this.size = 44,
  });

  final ZendCountry country;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        country.assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _InitialsBadge(
          country: country,
          size: size,
        ),
      ),
    );
  }
}

class _InitialsBadge extends StatelessWidget {
  const _InitialsBadge({required this.country, required this.size});
  final ZendCountry country;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: country.fallbackColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        country.initials,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: size * 0.27,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A shared PIN dots + spinner widget used across all PIN screens.
///
/// When [loading] is true the dots morph into a circular progress indicator
/// using a crossfade so the transition feels smooth and intentional.
class ZendPinDotsOrSpinner extends StatelessWidget {
  const ZendPinDotsOrSpinner({
    super.key,
    required this.filledCount,
    required this.loading,
    this.dotColor = ZendColors.accentPop,
    this.emptyBorderColor = const Color(0x66E8F4EC),
    this.spinnerColor = ZendColors.accentPop,
  });

  final int filledCount;
  final bool loading;
  final Color dotColor;
  final Color emptyBorderColor;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      crossFadeState:
          loading ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeIn,
      sizeCurve: Curves.easeInOut,
      alignment: Alignment.center,
      firstChild: _PinDots(
        filledCount: filledCount,
        dotColor: dotColor,
        emptyBorderColor: emptyBorderColor,
      ),
      secondChild: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: spinnerColor,
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.filledCount,
    required this.dotColor,
    required this.emptyBorderColor,
  });

  final int filledCount;
  final Color dotColor;
  final Color emptyBorderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final filled = index < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? dotColor : Colors.transparent,
              border: Border.all(
                color: filled ? dotColor : emptyBorderColor,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}
