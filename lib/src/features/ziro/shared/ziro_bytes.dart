/// Byte helpers for Ziro's wire formats (contracts.md §0–§2).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Uint8List zCat(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

Uint8List zUtf8(String s) => Uint8List.fromList(utf8.encode(s));

/// u64, little-endian, 8 bytes.
Uint8List zU64le(BigInt v) {
  if (v.isNegative || v.bitLength > 64) {
    throw ArgumentError.value(v, 'v', 'not a u64');
  }
  final out = Uint8List(8);
  var x = v;
  for (var i = 0; i < 8; i++) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

/// `I2OSP(n, 2)`: big-endian u16, as RFC 9180 writes lengths and ids.
Uint8List zI2osp2(int n) => Uint8List.fromList([(n >> 8) & 0xff, n & 0xff]);

String zHex(List<int> bytes) {
  final b = StringBuffer();
  for (final x in bytes) {
    b.write(x.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

Uint8List zUnhex(String hex) {
  var h = hex.trim().toLowerCase();
  if (h.startsWith('0x')) h = h.substring(2);
  h = h.replaceAll(RegExp(r'\s'), '');
  if (h.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(h)) {
    throw const FormatException('not hex');
  }
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// The 16 raw bytes of a hyphenated UUID.
Uint8List zUuidBytes(String uuid) {
  final h = uuid.replaceAll('-', '');
  if (h.length != 32) throw const FormatException('not a uuid');
  return zUnhex(h);
}

Uint8List zB64(String s) => Uint8List.fromList(base64.decode(s.trim()));

String zToB64(List<int> b) => base64.encode(b);

/// Length-independent comparison so a mismatch position doesn't leak timing.
bool zEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

Future<Uint8List> zSha256(List<int> data) async =>
    Uint8List.fromList((await Sha256().hash(data)).bytes);

/// Zeroes a buffer that held something sensitive (a PIN, an embedding).
void zWipe(List<int>? b) {
  if (b == null) return;
  for (var i = 0; i < b.length; i++) {
    b[i] = 0;
  }
}
