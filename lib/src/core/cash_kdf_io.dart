/// Native: pure-Dart Argon2id in a background isolate, so the UI keeps moving
/// during the few seconds it takes. Parameters documented in `cash_code.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

Future<Uint8List> deriveCashSeed(Uint8List password, Uint8List salt) =>
    compute(_derive, (password, salt));

Uint8List _derive((Uint8List, Uint8List) args) {
  final (password, salt) = args;
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 32,
        iterations: 1,
        memory: 65536,
        lanes: 1,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
  final out = Uint8List(32);
  generator.deriveKey(password, 0, out, 0);
  return out;
}
