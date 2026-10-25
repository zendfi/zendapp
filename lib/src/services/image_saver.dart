import 'dart:typed_data';

import 'image_saver_io.dart'
    if (dart.library.js_interop) 'image_saver_web.dart'
    as impl;

/// Saves a PNG to the user's photos on mobile (via `gal`), or downloads it
/// as a file in the browser. `gal` has no web implementation.
Future<void> saveImageBytes(Uint8List pngBytes, {String name = 'zend-qr'}) =>
    impl.saveImageBytes(pngBytes, name: name);
