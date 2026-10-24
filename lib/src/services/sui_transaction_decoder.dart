/// Strict BCS decoder for Sui `TransactionData`.
///
/// Exists so the device can read the bytes it is about to sign instead of
/// trusting them. The backend builds every transfer transaction and the client
/// previously signed the result blind — a compromised backend could not forge a
/// signature, but it could hand over bytes that said something other than what
/// the user asked for, and get them signed willingly.
///
/// ## Why decode rather than rebuild
///
/// The alternative is to rebuild the expected transaction locally and compare
/// bytes. That needs an *encoder*, and an encoder that is subtly wrong rejects
/// every transaction — a total send outage. A decoder that is subtly wrong fails
/// on the one shape it gets wrong, and this one is deliberately intolerant: any
/// unknown enum tag, any short read, any trailing byte is an error rather than
/// something skipped. Nothing is "parsed loosely and hoped for".
///
/// ## Encoding source
///
/// Taken from `sui-sdk-types` 0.3.2, which is the same crate the backend builds
/// with. Read off the Rust type definitions and the `serde` shims, **not** the
/// ABNF in the doc comments: those are stale, they omit `FundsWithdrawal`
/// entirely and they document `input-receiving` as tag `%x04` when the real
/// encoding nests it as `01 02` under an `Object` wrapper. The authority is
/// `src/transaction/serialization.rs`.
///
/// ```text
/// transaction      = %x00 transaction-v1
/// transaction-v1   = kind address gas-payment expiration
/// kind             = %x00 ptb
/// ptb              = vector(input) vector(command)
/// vector(t)        = uleb128 *t
/// input            = %x00 uleb128 OCTET      ; Pure
///                  / %x01 object-arg         ; Object
///                  / %x02 funds-withdrawal   ; FundsWithdrawal
/// object-arg       = %x00 object-ref / %x01 shared-input / %x02 object-ref
/// object-ref       = address u64 digest
/// shared-input     = address u64 bool
/// funds-withdrawal = reservation withdrawal-type withdraw-from
/// reservation      = %x00 u64                ; Amount
/// withdrawal-type  = %x00 type-tag           ; Balance
/// withdraw-from    = %x00 / %x01             ; Sender / Sponsor
/// command          = %x00 move-call / %x01-06 ...
/// move-call        = address identifier identifier vector(type-tag) vector(argument)
/// identifier       = uleb128 *UTF8
/// argument         = %x00 / %x01 u16 / %x02 u16 / %x03 u16 u16
/// type-tag         = %x00 bool / %x01 u8 / %x02 u64 / %x03 u128 / %x04 address
///                  / %x05 signer / %x06 type-tag / %x07 struct-tag
///                  / %x08 u16 / %x09 u32 / %x0a u256
/// struct-tag       = address identifier identifier vector(type-tag)
/// gas-payment      = vector(object-ref) address u64 u64
/// expiration       = %x00 / %x01 u64 / %x02 valid-during
/// valid-during     = option(u64) option(u64) option(u64) option(u64) digest u32
/// option(t)        = %x00 / %x01 t
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

/// Raised when bytes cannot be decoded as a Sui transaction.
///
/// Distinct from a verification failure: this means the payload is not a
/// transaction at all, or not one this decoder understands.
class SuiTransactionDecodeException implements Exception {
  const SuiTransactionDecodeException(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() => offset == null
      ? 'SuiTransactionDecodeException: $message'
      : 'SuiTransactionDecodeException: $message (at byte $offset)';
}

/// Sequential BCS reader.
///
/// Every read is bounds-checked, because the input is adversarial by assumption
/// — a malicious backend can send any bytes it likes, including a length prefix
/// claiming four billion elements.
class SuiBcsReader {
  SuiBcsReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;
  bool get isAtEnd => _offset >= _bytes.length;

  Never _fail(String message) =>
      throw SuiTransactionDecodeException(message, offset: _offset);

  void _need(int count) {
    if (count < 0 || remaining < count) {
      _fail('Expected $count more byte(s), found $remaining');
    }
  }

  int readU8() {
    _need(1);
    return _bytes[_offset++];
  }

  bool readBool() {
    final value = readU8();
    // BCS admits only 0 and 1. Anything else is a malformed payload, not a
    // truthy value.
    if (value > 1) _fail('Invalid bool byte 0x${value.toRadixString(16)}');
    return value == 1;
  }

  int readU16() {
    _need(2);
    final value = _bytes[_offset] | (_bytes[_offset + 1] << 8);
    _offset += 2;
    return value;
  }

  int readU32() {
    _need(4);
    final value =
        _bytes[_offset] |
        (_bytes[_offset + 1] << 8) |
        (_bytes[_offset + 2] << 16) |
        (_bytes[_offset + 3] << 24);
    _offset += 4;
    return value;
  }

  /// Read as [BigInt], not [int].
  ///
  /// A Dart `int` is 64-bit *signed*, so a hostile u64 above 2^63 would wrap to
  /// a negative number and could slip past a `<=` comparison on an amount.
  BigInt readU64() {
    _need(8);
    var value = BigInt.zero;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | BigInt.from(_bytes[_offset + i]);
    }
    _offset += 8;
    return value;
  }

  /// ULEB128, as BCS uses for every length prefix and enum-free integer.
  int readUleb128() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = readU8();
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
      // 5 groups of 7 bits covers u32, which is the documented bound for BCS
      // length prefixes. Refusing beyond that stops a padded encoding from
      // shifting into nonsense.
      if (shift > 28) _fail('ULEB128 value is too large');
    }
    if (result < 0) _fail('ULEB128 value overflowed');
    return result;
  }

  Uint8List readBytes(int count) {
    _need(count);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return Uint8List.fromList(value);
  }

  /// A length-prefixed byte string.
  Uint8List readByteVector() => readBytes(readUleb128());

  /// A 32-byte address, as lowercase `0x`-prefixed hex.
  ///
  /// Raw bytes with no length prefix: `Address` overrides serialization only
  /// for human-readable formats, so BCS uses the derived `[u8; 32]` tuple form.
  String readAddress() => _toHex(readBytes(32));

  /// A 32-byte digest, as lowercase `0x`-prefixed hex.
  ///
  /// **Length-prefixed**, unlike [readAddress]. `Digest` serializes through
  /// `serde_with::Bytes` in binary formats, and BCS writes a ULEB length before
  /// the bytes. Treating it as a bare 32-byte array misaligns everything that
  /// follows by one byte — which is exactly how the `ObjectReference` inside a
  /// gas payment was first found to be misread.
  String readDigest() {
    final length = readUleb128();
    if (length != 32) {
      _fail('Digest claims $length bytes, expected 32');
    }
    return _toHex(readBytes(32));
  }

  static String _toHex(Uint8List bytes) {
    final buffer = StringBuffer('0x');
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// A Move identifier: length-prefixed UTF-8.
  String readIdentifier() {
    final raw = readByteVector();
    try {
      return utf8.decode(raw);
    } on FormatException {
      _fail('Identifier is not valid UTF-8');
    }
  }

  /// A length-prefixed homogeneous sequence.
  List<T> readVector<T>(T Function() readElement) {
    final length = readUleb128();
    // Each element costs at least one byte, so a length prefix larger than the
    // remaining input is a lie and must not be used to preallocate.
    if (length > remaining) {
      _fail('Vector claims $length elements with only $remaining byte(s) left');
    }
    return List<T>.generate(length, (_) => readElement(), growable: false);
  }

  T? readOption<T>(T Function() readValue) {
    final tag = readU8();
    return switch (tag) {
      0 => null,
      1 => readValue(),
      _ => _fail('Invalid Option tag 0x${tag.toRadixString(16)}'),
    };
  }

  /// Asserts the payload ended exactly here.
  ///
  /// Trailing bytes mean the sender appended something the decoder did not
  /// account for, which is precisely the case this class exists to catch.
  void expectEnd() {
    if (!isAtEnd) _fail('$remaining unexpected trailing byte(s)');
  }
}

/// A Move type argument, flattened to its canonical string form.
class SuiTypeTag {
  const SuiTypeTag(this.canonical);

  /// Canonical textual form, for example `0x2::sui::SUI`.
  final String canonical;

  static SuiTypeTag read(SuiBcsReader reader, {int depth = 0}) {
    // Type tags nest (vectors, generic parameters). A hostile payload could
    // nest them thousands deep to exhaust the stack, so cap the recursion.
    if (depth > 16) {
      throw const SuiTransactionDecodeException('Type tag nesting is too deep');
    }
    final tag = reader.readU8();
    switch (tag) {
      case 0:
        return const SuiTypeTag('bool');
      case 1:
        return const SuiTypeTag('u8');
      case 2:
        return const SuiTypeTag('u64');
      case 3:
        return const SuiTypeTag('u128');
      case 4:
        return const SuiTypeTag('address');
      case 5:
        return const SuiTypeTag('signer');
      case 6:
        final inner = read(reader, depth: depth + 1);
        return SuiTypeTag('vector<${inner.canonical}>');
      case 7:
        return SuiTypeTag(_readStructTag(reader, depth: depth + 1));
      case 8:
        return const SuiTypeTag('u16');
      case 9:
        return const SuiTypeTag('u32');
      case 10:
        return const SuiTypeTag('u256');
      default:
        throw SuiTransactionDecodeException(
          'Unknown type tag 0x${tag.toRadixString(16)}',
          offset: reader.offset,
        );
    }
  }

  static String _readStructTag(SuiBcsReader reader, {required int depth}) {
    final address = reader.readAddress();
    final module = reader.readIdentifier();
    final name = reader.readIdentifier();
    final params = reader.readVector(() => read(reader, depth: depth));
    final base = '$address::$module::$name';
    if (params.isEmpty) return base;
    return '$base<${params.map((p) => p.canonical).join(',')}>';
  }

  @override
  String toString() => canonical;
}

/// Reference to an on-chain object.
class SuiObjectReference {
  const SuiObjectReference({
    required this.objectId,
    required this.version,
    required this.digest,
  });

  final String objectId;
  final BigInt version;
  final String digest;

  static SuiObjectReference read(SuiBcsReader reader) => SuiObjectReference(
    objectId: reader.readAddress(),
    version: reader.readU64(),
    digest: reader.readDigest(),
  );
}

/// Where a funds withdrawal draws from.
enum SuiWithdrawFrom { sender, sponsor }

/// A transaction input.
sealed class SuiInput {
  const SuiInput();

  static SuiInput read(SuiBcsReader reader) {
    final tag = reader.readU8();
    switch (tag) {
      case 0:
        return SuiPureInput(reader.readByteVector());
      case 1:
        final objectTag = reader.readU8();
        return switch (objectTag) {
          0 => SuiObjectInput(
            kind: SuiObjectInputKind.immutableOrOwned,
            reference: SuiObjectReference.read(reader),
          ),
          1 => _readSharedInput(reader),
          2 => SuiObjectInput(
            kind: SuiObjectInputKind.receiving,
            reference: SuiObjectReference.read(reader),
          ),
          _ => throw SuiTransactionDecodeException(
            'Unknown object input tag 0x${objectTag.toRadixString(16)}',
            offset: reader.offset,
          ),
        };
      case 2:
        return SuiFundsWithdrawalInput.read(reader);
      default:
        throw SuiTransactionDecodeException(
          'Unknown input tag 0x${tag.toRadixString(16)}',
          offset: reader.offset,
        );
    }
  }

  static SuiInput _readSharedInput(SuiBcsReader reader) {
    final objectId = reader.readAddress();
    final initialSharedVersion = reader.readU64();
    final mutable = reader.readBool();
    return SuiSharedInput(
      objectId: objectId,
      initialSharedVersion: initialSharedVersion,
      mutable: mutable,
    );
  }
}

/// Inline bytes, used for plain values such as an address or an amount.
class SuiPureInput extends SuiInput {
  const SuiPureInput(this.bytes);

  final Uint8List bytes;

  /// Reads these bytes as a 32-byte address, or null when they are not one.
  String? get asAddress {
    if (bytes.length != 32) return null;
    final buffer = StringBuffer('0x');
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

enum SuiObjectInputKind { immutableOrOwned, receiving }

class SuiObjectInput extends SuiInput {
  const SuiObjectInput({required this.kind, required this.reference});

  final SuiObjectInputKind kind;
  final SuiObjectReference reference;
}

class SuiSharedInput extends SuiInput {
  const SuiSharedInput({
    required this.objectId,
    required this.initialSharedVersion,
    required this.mutable,
  });

  final String objectId;
  final BigInt initialSharedVersion;
  final bool mutable;
}

/// A withdrawal from an address balance accumulator.
///
/// This is where the amount of a gasless transfer lives — there is no coin
/// object to inspect, so this is the only place the value appears.
class SuiFundsWithdrawalInput extends SuiInput {
  const SuiFundsWithdrawalInput({
    required this.amount,
    required this.coinType,
    required this.source,
  });

  final BigInt amount;
  final SuiTypeTag coinType;
  final SuiWithdrawFrom source;

  static SuiFundsWithdrawalInput read(SuiBcsReader reader) {
    final reservationTag = reader.readU8();
    if (reservationTag != 0) {
      throw SuiTransactionDecodeException(
        'Unknown reservation tag 0x${reservationTag.toRadixString(16)}',
        offset: reader.offset,
      );
    }
    final amount = reader.readU64();

    final withdrawalTypeTag = reader.readU8();
    if (withdrawalTypeTag != 0) {
      throw SuiTransactionDecodeException(
        'Unknown withdrawal type tag 0x${withdrawalTypeTag.toRadixString(16)}',
        offset: reader.offset,
      );
    }
    final coinType = SuiTypeTag.read(reader);

    final sourceTag = reader.readU8();
    final source = switch (sourceTag) {
      0 => SuiWithdrawFrom.sender,
      1 => SuiWithdrawFrom.sponsor,
      _ => throw SuiTransactionDecodeException(
        'Unknown withdraw-from tag 0x${sourceTag.toRadixString(16)}',
        offset: reader.offset,
      ),
    };

    return SuiFundsWithdrawalInput(
      amount: amount,
      coinType: coinType,
      source: source,
    );
  }
}

/// Reference to a value available to a command.
class SuiArgument {
  const SuiArgument({required this.kind, this.index, this.resultIndex});

  final SuiArgumentKind kind;
  final int? index;
  final int? resultIndex;

  static SuiArgument read(SuiBcsReader reader) {
    final tag = reader.readU8();
    switch (tag) {
      case 0:
        return const SuiArgument(kind: SuiArgumentKind.gas);
      case 1:
        return SuiArgument(kind: SuiArgumentKind.input, index: reader.readU16());
      case 2:
        return SuiArgument(
          kind: SuiArgumentKind.result,
          index: reader.readU16(),
        );
      case 3:
        final index = reader.readU16();
        final resultIndex = reader.readU16();
        return SuiArgument(
          kind: SuiArgumentKind.nestedResult,
          index: index,
          resultIndex: resultIndex,
        );
      default:
        throw SuiTransactionDecodeException(
          'Unknown argument tag 0x${tag.toRadixString(16)}',
          offset: reader.offset,
        );
    }
  }
}

enum SuiArgumentKind { gas, input, result, nestedResult }

/// A single PTB command.
sealed class SuiCommand {
  const SuiCommand();

  static SuiCommand read(SuiBcsReader reader) {
    final tag = reader.readU8();
    switch (tag) {
      case 0:
        return SuiMoveCallCommand.read(reader);
      case 1:
        final objects = reader.readVector(() => SuiArgument.read(reader));
        final address = SuiArgument.read(reader);
        return SuiTransferObjectsCommand(objects: objects, address: address);
      case 2:
        final coin = SuiArgument.read(reader);
        final amounts = reader.readVector(() => SuiArgument.read(reader));
        return SuiSplitCoinsCommand(coin: coin, amounts: amounts);
      case 3:
        final coin = SuiArgument.read(reader);
        final toMerge = reader.readVector(() => SuiArgument.read(reader));
        return SuiMergeCoinsCommand(coin: coin, coinsToMerge: toMerge);
      case 4:
        final modules = reader.readVector(() => reader.readByteVector());
        final dependencies = reader.readVector(() => reader.readAddress());
        return SuiPublishCommand(
          moduleCount: modules.length,
          dependencies: dependencies,
        );
      case 5:
        final elementType = reader.readOption(() => SuiTypeTag.read(reader));
        final elements = reader.readVector(() => SuiArgument.read(reader));
        return SuiMakeMoveVectorCommand(
          elementType: elementType,
          elements: elements,
        );
      case 6:
        final modules = reader.readVector(() => reader.readByteVector());
        final dependencies = reader.readVector(() => reader.readAddress());
        final package = reader.readAddress();
        final ticket = SuiArgument.read(reader);
        return SuiUpgradeCommand(
          moduleCount: modules.length,
          dependencies: dependencies,
          package: package,
          ticket: ticket,
        );
      default:
        throw SuiTransactionDecodeException(
          'Unknown command tag 0x${tag.toRadixString(16)}',
          offset: reader.offset,
        );
    }
  }

  /// Short description for error messages shown to a human.
  String get label;
}

class SuiMoveCallCommand extends SuiCommand {
  const SuiMoveCallCommand({
    required this.package,
    required this.module,
    required this.function,
    required this.typeArguments,
    required this.arguments,
  });

  final String package;
  final String module;
  final String function;
  final List<SuiTypeTag> typeArguments;
  final List<SuiArgument> arguments;

  /// `package::module::function`, with the package in full rather than
  /// abbreviated — `0x2` and a lookalike package must not render identically.
  String get target => '$package::$module::$function';

  static SuiMoveCallCommand read(SuiBcsReader reader) {
    final package = reader.readAddress();
    final module = reader.readIdentifier();
    final function = reader.readIdentifier();
    final typeArguments = reader.readVector(() => SuiTypeTag.read(reader));
    final arguments = reader.readVector(() => SuiArgument.read(reader));
    return SuiMoveCallCommand(
      package: package,
      module: module,
      function: function,
      typeArguments: typeArguments,
      arguments: arguments,
    );
  }

  @override
  String get label => 'a call to $target';
}

class SuiTransferObjectsCommand extends SuiCommand {
  const SuiTransferObjectsCommand({
    required this.objects,
    required this.address,
  });

  final List<SuiArgument> objects;
  final SuiArgument address;

  @override
  String get label => 'an object transfer';
}

class SuiSplitCoinsCommand extends SuiCommand {
  const SuiSplitCoinsCommand({required this.coin, required this.amounts});

  final SuiArgument coin;
  final List<SuiArgument> amounts;

  @override
  String get label => 'a coin split';
}

class SuiMergeCoinsCommand extends SuiCommand {
  const SuiMergeCoinsCommand({required this.coin, required this.coinsToMerge});

  final SuiArgument coin;
  final List<SuiArgument> coinsToMerge;

  @override
  String get label => 'a coin merge';
}

class SuiPublishCommand extends SuiCommand {
  const SuiPublishCommand({
    required this.moduleCount,
    required this.dependencies,
  });

  final int moduleCount;
  final List<String> dependencies;

  @override
  String get label => 'a package publish';
}

class SuiMakeMoveVectorCommand extends SuiCommand {
  const SuiMakeMoveVectorCommand({
    required this.elementType,
    required this.elements,
  });

  final SuiTypeTag? elementType;
  final List<SuiArgument> elements;

  @override
  String get label => 'a Move vector construction';
}

class SuiUpgradeCommand extends SuiCommand {
  const SuiUpgradeCommand({
    required this.moduleCount,
    required this.dependencies,
    required this.package,
    required this.ticket,
  });

  final int moduleCount;
  final List<String> dependencies;
  final String package;
  final SuiArgument ticket;

  @override
  String get label => 'a package upgrade';
}

/// How gas is paid.
class SuiGasPayment {
  const SuiGasPayment({
    required this.objects,
    required this.owner,
    required this.price,
    required this.budget,
  });

  final List<SuiObjectReference> objects;
  final String owner;
  final BigInt price;
  final BigInt budget;

  /// A gasless stablecoin transfer is marked by zero price, zero budget and no
  /// gas coins. Anything else means the user is paying, from somewhere.
  bool get isGasless =>
      objects.isEmpty && price == BigInt.zero && budget == BigInt.zero;

  static SuiGasPayment read(SuiBcsReader reader) => SuiGasPayment(
    objects: reader.readVector(() => SuiObjectReference.read(reader)),
    owner: reader.readAddress(),
    price: reader.readU64(),
    budget: reader.readU64(),
  );
}

/// When a transaction may execute.
sealed class SuiExpiration {
  const SuiExpiration();

  static SuiExpiration read(SuiBcsReader reader) {
    final tag = reader.readU8();
    switch (tag) {
      case 0:
        return const SuiNoExpiration();
      case 1:
        return SuiEpochExpiration(reader.readU64());
      case 2:
        final minEpoch = reader.readOption(() => reader.readU64());
        final maxEpoch = reader.readOption(() => reader.readU64());
        final minTimestamp = reader.readOption(() => reader.readU64());
        final maxTimestamp = reader.readOption(() => reader.readU64());
        final chain = reader.readDigest();
        final nonce = reader.readU32();
        return SuiValidDuringExpiration(
          minEpoch: minEpoch,
          maxEpoch: maxEpoch,
          minTimestamp: minTimestamp,
          maxTimestamp: maxTimestamp,
          chain: chain,
          nonce: nonce,
        );
      default:
        throw SuiTransactionDecodeException(
          'Unknown expiration tag 0x${tag.toRadixString(16)}',
          offset: reader.offset,
        );
    }
  }
}

class SuiNoExpiration extends SuiExpiration {
  const SuiNoExpiration();
}

class SuiEpochExpiration extends SuiExpiration {
  const SuiEpochExpiration(this.epoch);

  final BigInt epoch;
}

/// The bounded form a gasless transfer must use, since it has no object
/// versions to make it unique. `chain` is what stops the same signed bytes
/// being replayed on another network.
class SuiValidDuringExpiration extends SuiExpiration {
  const SuiValidDuringExpiration({
    required this.minEpoch,
    required this.maxEpoch,
    required this.minTimestamp,
    required this.maxTimestamp,
    required this.chain,
    required this.nonce,
  });

  final BigInt? minEpoch;
  final BigInt? maxEpoch;
  final BigInt? minTimestamp;
  final BigInt? maxTimestamp;
  final String chain;
  final int nonce;
}

/// A fully decoded Sui transaction.
class SuiDecodedTransaction {
  const SuiDecodedTransaction({
    required this.inputs,
    required this.commands,
    required this.sender,
    required this.gasPayment,
    required this.expiration,
  });

  final List<SuiInput> inputs;
  final List<SuiCommand> commands;
  final String sender;
  final SuiGasPayment gasPayment;
  final SuiExpiration expiration;
}

/// Decodes `TransactionData` BCS bytes.
///
/// Throws [SuiTransactionDecodeException] on anything unexpected, including
/// trailing bytes. Never returns a partially understood transaction.
SuiDecodedTransaction decodeSuiTransaction(Uint8List transactionDataBcs) {
  if (transactionDataBcs.isEmpty) {
    throw const SuiTransactionDecodeException('Transaction bytes are empty');
  }
  final reader = SuiBcsReader(transactionDataBcs);

  final version = reader.readU8();
  if (version != 0) {
    throw SuiTransactionDecodeException(
      'Unsupported TransactionData version 0x${version.toRadixString(16)}',
      offset: 0,
    );
  }

  final kind = reader.readU8();
  if (kind != 0) {
    // Everything other than tag 0 is a system transaction. A user wallet has no
    // business signing one, so refuse rather than decode it.
    throw SuiTransactionDecodeException(
      'Transaction kind 0x${kind.toRadixString(16)} is not a programmable '
      'transaction',
      offset: reader.offset,
    );
  }

  final inputs = reader.readVector(() => SuiInput.read(reader));
  final commands = reader.readVector(() => SuiCommand.read(reader));
  final sender = reader.readAddress();
  final gasPayment = SuiGasPayment.read(reader);
  final expiration = SuiExpiration.read(reader);
  reader.expectEnd();

  return SuiDecodedTransaction(
    inputs: inputs,
    commands: commands,
    sender: sender,
    gasPayment: gasPayment,
    expiration: expiration,
  );
}
