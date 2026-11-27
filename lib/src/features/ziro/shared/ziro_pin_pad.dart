import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../design/zend_tokens.dart';

/// A permutation of 0–9 that differs from [previous] (when given), from a
/// cryptographically secure source unless [random] is supplied (tests).
List<int> ziroShuffledDigits({List<int>? previous, Random? random}) {
  final r = random ?? Random.secure();
  while (true) {
    final d = List<int>.generate(10, (i) => i)..shuffle(r);
    if (previous == null || !_same(d, previous)) return d;
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A 4-digit PIN pad. With [shuffle], the digits sit in a new order every
/// time it is shown and every time [ZiroPinPadState.reshuffle] is called, so
/// someone watching the hand can't learn the PIN from its position [R5.7].
class ZiroPinPad extends StatefulWidget {
  const ZiroPinPad({
    super.key,
    required this.onComplete,
    this.shuffle = true,
    this.length = 4,
    this.random,
    this.enabled = true,
    this.dark = false,
  });

  /// Called with the PIN once [length] digits are in. The pad clears itself.
  final ValueChanged<String> onComplete;
  final bool shuffle;
  final int length;
  final Random? random;
  final bool enabled;

  /// Light keys on a dark screen (the till's customer view).
  final bool dark;

  @override
  State<ZiroPinPad> createState() => ZiroPinPadState();
}

class ZiroPinPadState extends State<ZiroPinPad> {
  late List<int> _layout;
  final List<int> _digits = [];

  /// The digits in reading order (rows of three, then the last one).
  List<int> get layout => List.unmodifiable(_layout);
  int get entered => _digits.length;

  @override
  void initState() {
    super.initState();
    _layout = widget.shuffle
        ? ziroShuffledDigits(random: widget.random)
        : const [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
  }

  /// New positions for every digit, and clears what was typed.
  void reshuffle() {
    setState(() {
      _clear();
      if (widget.shuffle) {
        _layout = ziroShuffledDigits(previous: _layout, random: widget.random);
      }
    });
  }

  void clear() => setState(_clear);

  void _clear() {
    for (var i = 0; i < _digits.length; i++) {
      _digits[i] = 0;
    }
    _digits.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _tap(int d) {
    if (!widget.enabled || _digits.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _digits.add(d));
    if (_digits.length == widget.length) {
      final pin = _digits.join();
      setState(_clear);
      widget.onComplete(pin);
    }
  }

  void _back() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits[_digits.length - 1] = 0;
      _digits.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final fg = widget.dark ? Colors.white : zt.textPrimary;
    final keyBg = widget.dark
        ? Colors.white.withValues(alpha: 0.10)
        : zt.bgSecondary;

    Widget key(Widget child, VoidCallback? onTap, {Key? k, String? label}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Semantics(
              button: true,
              label: label,
              child: Material(
                color: onTap == null ? Colors.transparent : keyBg,
                borderRadius: BorderRadius.circular(ZendRadii.lg),
                child: InkWell(
                  key: k,
                  borderRadius: BorderRadius.circular(ZendRadii.lg),
                  onTap: widget.enabled ? onTap : null,
                  child: SizedBox(height: 64, child: Center(child: child)),
                ),
              ),
            ),
          ),
        );

    Widget digit(int d) => key(
      Text(
        '$d',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
      () => _tap(d),
      k: Key('ziro-pin-key-$d'),
      label: '$d',
    );

    final rows = <Widget>[
      for (var r = 0; r < 3; r++)
        Row(children: [for (var c = 0; c < 3; c++) digit(_layout[r * 3 + c])]),
      Row(
        children: [
          key(const SizedBox.shrink(), null),
          digit(_layout[9]),
          key(
            Icon(PhosphorIconsRegular.backspace, color: fg),
            _back,
            k: const Key('ziro-pin-back'),
            label: 'Delete',
          ),
        ],
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.length; i++)
              AnimatedContainer(
                duration: ZendMotion.quick,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _digits.length ? fg : Colors.transparent,
                  border: Border.all(color: fg, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        ...rows,
      ],
    );
  }
}
