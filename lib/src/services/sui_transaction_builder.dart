/// Builds a gasless USDC transfer with no network (offline payments, R21.1).
///
/// The same shape `build_gasless_transfer` makes on the server, written byte
/// for byte as BCS `TransactionData`:
///
/// - inputs `[FundsWithdrawal(amount, Balance of coin, sender), Pure(recipient)]`
/// - commands `[0x2::balance::redeem_funds(Input 0),
///              0x2::balance::send_funds(Result 0, Input 1)]`, both of coin
/// - gas price 0, budget 0, no gas objects, owner = sender
/// - `ValidDuring { min_epoch, max_epoch, chain, nonce }`
///
/// [decodeSuiTransaction] reads it back; the payer's app verifies the result
/// before signing, the same as a server-built send.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class SuiBcsWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u8(int v) => _b.addByte(v & 0xff);
  void u16(int v) {
    u8(v);
    u8(v >> 8);
  }

  void u32(int v) {
    for (var i = 0; i < 4; i++) {
      u8(v >> (8 * i));
    }
  }

  void u64(BigInt v) {
    if (v.isNegative || v.bitLength > 64) {
      throw ArgumentError('u64 out of range: $v');
    }
    for (var i = 0; i < 8; i++) {
      u8(((v >> (8 * i)) & BigInt.from(0xff)).toInt());
    }
  }

  void uleb(int v) {
    var n = v;
    while (true) {
      final byte = n & 0x7f;
      n >>= 7;
      if (n == 0) {
        u8(byte);
        return;
      }
      u8(byte | 0x80);
    }
  }

  void raw(List<int> bytes) => _b.add(bytes);
  void bytes(List<int> v) {
    uleb(v.length);
    raw(v);
  }

  void identifier(String s) => bytes(utf8.encode(s));
  void address(String hex) => raw(suiAddressBytes(hex));

  Uint8List take() => _b.takeBytes();
}

/// A `0x…` address or object id as 32 bytes (left-padded).
Uint8List suiAddressBytes(String hex) {
  var h = hex.trim().toLowerCase();
  if (h.startsWith('0x')) h = h.substring(2);
  if (h.isEmpty || h.length > 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(h)) {
    throw ArgumentError('Not a Sui address: $hex');
  }
  h = h.padLeft(64, '0');
  return Uint8List.fromList([
    for (var i = 0; i < 64; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
  ]);
}

/// `0xaddr::module::Name` (no type parameters) as a BCS `TypeTag::Struct`.
void _writeStructTag(SuiBcsWriter w, String coinType) {
  final parts = coinType.split('::');
  if (parts.length != 3 || coinType.contains('<')) {
    throw ArgumentError('Unsupported coin type: $coinType');
  }
  w.u8(7); // TypeTag::Struct
  w.address(parts[0]);
  w.identifier(parts[1]);
  w.identifier(parts[2]);
  w.uleb(0); // no type parameters
}

/// Base64 BCS `TransactionData` for a gasless transfer of [amountBaseUnits]
/// of [coinType] from [sender] to [recipient], valid for epochs
/// `minEpoch..=maxEpoch` on the chain whose 32-byte id is [chainIdHex].
String buildGaslessTransfer({
  required String sender,
  required String recipient,
  required String coinType,
  required BigInt amountBaseUnits,
  required String chainIdHex,
  required int minEpoch,
  required int maxEpoch,
  int? nonce,
}) {
  if (amountBaseUnits <= BigInt.zero) {
    throw ArgumentError('Amount must be positive');
  }
  if (maxEpoch < minEpoch || maxEpoch > minEpoch + 1) {
    throw ArgumentError('A gasless transfer is valid for at most two epochs');
  }
  final w = SuiBcsWriter();
  w.u8(0); // TransactionData::V1
  w.u8(0); // TransactionKind::ProgrammableTransaction
  // Inputs.
  w.uleb(2);
  w.u8(2); // Input::FundsWithdrawal
  w.u8(0); // Reservation::Amount
  w.u64(amountBaseUnits);
  w.u8(0); // WithdrawalType::Balance
  _writeStructTag(w, coinType);
  w.u8(0); // WithdrawFrom::Sender
  w.u8(0); // Input::Pure
  w.bytes(suiAddressBytes(recipient));
  // Commands.
  void balanceCall(String function, List<void Function()> args) {
    w.u8(0); // Command::MoveCall
    w.address('0x2');
    w.identifier('balance');
    w.identifier(function);
    w.uleb(1);
    _writeStructTag(w, coinType);
    w.uleb(args.length);
    for (final a in args) {
      a();
    }
  }

  w.uleb(2);
  balanceCall('redeem_funds', [
    () {
      w.u8(1); // Argument::Input
      w.u16(0);
    },
  ]);
  balanceCall('send_funds', [
    () {
      w.u8(2); // Argument::Result
      w.u16(0);
    },
    () {
      w.u8(1); // Argument::Input
      w.u16(1);
    },
  ]);
  // Sender and gas: gasless.
  w.address(sender);
  w.uleb(0); // no gas objects
  w.address(sender); // gas owner
  w.u64(BigInt.zero); // price
  w.u64(BigInt.zero); // budget
  // Expiration: ValidDuring.
  w.u8(2);
  w.u8(1);
  w.u64(BigInt.from(minEpoch));
  w.u8(1);
  w.u64(BigInt.from(maxEpoch));
  w.u8(0); // no min timestamp
  w.u8(0); // no max timestamp
  w.bytes(suiAddressBytes(chainIdHex)); // Digest: length-prefixed 32 bytes
  w.u32(nonce ?? randomU32());
  return base64.encode(w.take());
}

/// A random u32 that also works on web. `1 << 32` is 0 in a browser (JavaScript's
/// 32-bit shifts), so `nextInt(1 << 32)` threw there. Two 16-bit halves combined by
/// multiplication stay exact on both platforms.
int randomU32([Random? random]) {
  final r = random ?? Random.secure();
  return r.nextInt(0x10000) * 0x10000 + r.nextInt(0x10000);
}
