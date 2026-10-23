import 'dart:typed_data';

import 'package:gal/gal.dart';

Future<void> saveImageBytes(Uint8List pngBytes, {required String name}) =>
    Gal.putImageBytes(pngBytes, name: name);
