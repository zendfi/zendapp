import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

web.HTMLElement? _probe;

/// Reads `env(safe-area-inset-*)` from a hidden element padded by them.
/// Cheap: one style read; called when the window size changes.
EdgeInsets webSafeAreaInsets() {
  try {
    final probe = _probe ??= _createProbe();
    final style = web.window.getComputedStyle(probe);
    double px(String side) =>
        double.tryParse(
          style.getPropertyValue('padding-$side').replaceAll('px', '').trim(),
        ) ??
        0;
    return EdgeInsets.fromLTRB(
      px('left'),
      px('top'),
      px('right'),
      px('bottom'),
    );
  } catch (_) {
    return EdgeInsets.zero;
  }
}

web.HTMLElement _createProbe() {
  final probe = web.document.createElement('div') as web.HTMLElement
    ..id = 'zend-safe-area-probe'
    ..setAttribute('aria-hidden', 'true');
  probe.style.cssText =
      'position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;'
      'pointer-events:none;'
      'padding:env(safe-area-inset-top) env(safe-area-inset-right) '
      'env(safe-area-inset-bottom) env(safe-area-inset-left);';
  web.document.body!.append(probe);
  return probe;
}
