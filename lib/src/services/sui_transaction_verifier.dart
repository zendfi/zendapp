/// Checks that a backend-built Sui transfer says what the user asked for.
///
/// The backend constructs every transfer and the device signs the result. A
/// compromised backend cannot forge a zkLogin signature — the ephemeral key
/// never leaves the device and the JWT nonce binds the proof to it — but it can
/// hand over bytes that mean something other than the user's intent and have
/// them signed willingly. This closes that gap for everything the device can
/// establish on its own.
///
/// ## What is checked without trusting the backend
///
/// The device independently knows two things: its **own address**, and the
/// **amount the user typed**. Everything below follows from those plus the
/// fixed shape a gasless transfer is required to have:
///
///   * the sender is this wallet, not some other address,
///   * the withdrawal amount equals the amount the user entered,
///   * the funds come from the *sender's* accumulator, not a sponsor's,
///   * there are exactly two commands — `0x2::balance::redeem_funds` then
///     `0x2::balance::send_funds` — wired withdrawal → redeemed balance →
///     recipient, and nothing else is appended,
///   * there are exactly two inputs and nothing else is smuggled in,
///   * gas is zero-priced, zero-budget and unfunded, so no coin is drained,
///   * the transaction is epoch-bounded,
///   * no unknown enum tag and no trailing byte anywhere.
///
/// Together these defeat the realistic attacks: inflating the amount, and
/// appending a second command that moves something the user never saw.
///
/// ## What cannot be checked here, and why
///
/// **The recipient.** The client sends a *zendtag* and the backend resolves it
/// to an address; the prepare response carries neither the address nor the
/// amount back. So the device has no independent zendtag→address mapping, and a
/// backend willing to lie in the transaction will lie everywhere else the
/// client could look. Verifying the recipient needs a trust anchor outside the
/// backend — pinning the address per zendtag on first use is the cheapest one,
/// and [expectedRecipient] is the hook for it.
///
/// **Chain identifier and coin type** are fixed public per-network values, but
/// they are backend-configured with no defaults, so this file does not hardcode
/// a guess: a wrong constant would reject every transfer. [expectedChain] and
/// [expectedCoinType] engage once a pinned value exists.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'sui_transaction_decoder.dart';

/// The `0x2::balance::send_funds` call a gasless transfer is required to be.
const _kBalancePackage =
    '0x0000000000000000000000000000000000000000000000000000000000000002';
const _kBalanceModule = 'balance';
const _kSendFundsFunction = 'send_funds';
const _kRedeemFundsFunction = 'redeem_funds';

/// Raised when the bytes do not match what the user asked for.
///
/// Separate from [SuiTransactionDecodeException]: that means "not a transaction
/// I understand", this means "a transaction that does the wrong thing".
class SuiTransactionVerificationException implements Exception {
  const SuiTransactionVerificationException(this.reason);

  /// Technical detail, for logs and diagnostics.
  final String reason;

  /// Deliberately vague and identical for every cause.
  ///
  /// The specific mismatch is useful to an engineer and useless to a user, who
  /// cannot act on "withdrawal source is sponsor". It is also not worth handing
  /// an attacker a probe that reports exactly which check caught them.
  String get userMessage =>
      'This payment could not be verified on your device and was not signed. '
      'Nothing has left your account.';

  @override
  String toString() => 'SuiTransactionVerificationException: $reason';
}

/// What the device expects the transaction to say.
class SuiTransferExpectation {
  const SuiTransferExpectation({
    required this.amountBaseUnits,
    this.senderAddress,
    this.expectedRecipient,
    this.expectedCoinType,
    this.expectedChain,
  });

  /// This wallet's own address, when the caller has it to hand.
  ///
  /// Optional because it is a consistency check rather than a trust anchor: the
  /// zkLogin authenticator is only valid for the address derived from the
  /// identity's salt and subject, so a substituted sender produces a signature
  /// that fails on-chain rather than one that moves someone else's money. The
  /// internal checks below use the transaction's own sender regardless.
  final String? senderAddress;

  /// The amount the user entered, in base units.
  ///
  /// [BigInt] rather than `int` because the decoded value is an unsigned 64-bit
  /// integer: a hostile amount above 2^63 would wrap negative in a Dart `int`
  /// and could compare as less than the expected value.
  final BigInt amountBaseUnits;

  /// Pinned recipient address for this zendtag, when one is known.
  final String? expectedRecipient;

  /// Pinned USDC type for this network, when one is known.
  final String? expectedCoinType;

  /// Pinned chain identifier for this network, when one is known.
  final String? expectedChain;
}

/// What the transaction was found to say. Returned so the caller can pin values
/// it had no expectation for yet.
class SuiVerifiedTransfer {
  const SuiVerifiedTransfer({
    required this.recipientAddress,
    required this.amountBaseUnits,
    required this.coinType,
    required this.chain,
  });

  final String recipientAddress;
  final BigInt amountBaseUnits;
  final String coinType;
  final String chain;
}

/// Normalises a Sui address for comparison.
///
/// Addresses appear in both abbreviated (`0x2`) and full 32-byte form, and
/// casing varies. Comparing raw strings would make a correct address look wrong.
String normaliseSuiAddress(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.startsWith('0x')) value = value.substring(2);
  if (value.isEmpty || value.length > 64) {
    throw SuiTransactionVerificationException(
      'Address "$raw" is not a valid Sui address',
    );
  }
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw SuiTransactionVerificationException(
      'Address "$raw" contains non-hex characters',
    );
  }
  return '0x${value.padLeft(64, '0')}';
}

/// Decodes [transactionDataBcsBase64] and checks it against [expectation].
///
/// Returns what the transaction says on success. Throws
/// [SuiTransactionVerificationException] on any mismatch and
/// [SuiTransactionDecodeException] if the bytes are not a transaction at all.
/// Never returns normally for a transaction it could not fully account for.
SuiVerifiedTransfer verifyGaslessUsdcTransfer({
  required String transactionDataBcsBase64,
  required SuiTransferExpectation expectation,
}) {
  final Uint8List bytes;
  try {
    bytes = base64.decode(transactionDataBcsBase64.trim());
  } on FormatException catch (error) {
    throw SuiTransactionDecodeException(
      'Transaction payload is not valid base64: ${error.message}',
    );
  }

  // Strict: throws on unknown tags, short reads and trailing bytes, so
  // everything below is reasoning about a fully accounted-for transaction
  // rather than a best-effort parse.
  final transaction = decodeSuiTransaction(bytes);

  // ── Sender ──
  // The transaction's own sender anchors the internal checks; comparing it to a
  // locally held address is an extra when one is available.
  final expectedSender = normaliseSuiAddress(transaction.sender);
  final claimedSender = expectation.senderAddress;
  if (claimedSender != null &&
      normaliseSuiAddress(claimedSender) != expectedSender) {
    throw SuiTransactionVerificationException(
      'Sender is $expectedSender, expected '
      '${normaliseSuiAddress(claimedSender)}',
    );
  }

  // ── Gas ──
  // Zero price, zero budget, no gas coins. A non-gasless shape here would mean
  // the user is paying from an object this flow never intends to touch.
  if (!transaction.gasPayment.isGasless) {
    throw SuiTransactionVerificationException(
      'Transaction is not gasless: '
      '${transaction.gasPayment.objects.length} gas object(s), '
      'price ${transaction.gasPayment.price}, '
      'budget ${transaction.gasPayment.budget}',
    );
  }
  final gasOwner = normaliseSuiAddress(transaction.gasPayment.owner);
  if (gasOwner != expectedSender) {
    throw SuiTransactionVerificationException(
      'Gas owner is $gasOwner, expected $expectedSender',
    );
  }

  // ── Commands ──
  // A gasless address-balance transfer is exactly two commands, in order:
  //   0. `0x2::balance::redeem_funds<T>(withdrawal)` → a `Balance<T>`,
  //   1. `0x2::balance::send_funds<T>(that balance, recipient)`.
  // Both are on the protocol's gasless allowlist. Pinning the count at two and
  // the wiring between them (withdrawal → redeem result → send) is what stops
  // any *other* command being appended to an otherwise correct transfer.
  if (transaction.commands.length != 2) {
    throw SuiTransactionVerificationException(
      'Expected exactly 2 commands, found ${transaction.commands.length}: '
      '${transaction.commands.map((c) => c.label).join(', ')}',
    );
  }

  // Command 0: redeem_funds<T>(input 0).
  final redeemCommand = transaction.commands[0];
  if (redeemCommand is! SuiMoveCallCommand) {
    throw SuiTransactionVerificationException(
      'Command 0 is not a Move call, found ${redeemCommand.label}',
    );
  }
  if (normaliseSuiAddress(redeemCommand.package) != _kBalancePackage ||
      redeemCommand.module != _kBalanceModule ||
      redeemCommand.function != _kRedeemFundsFunction) {
    throw SuiTransactionVerificationException(
      'Expected $_kBalancePackage::$_kBalanceModule::$_kRedeemFundsFunction, '
      'found ${redeemCommand.target}',
    );
  }
  if (redeemCommand.typeArguments.length != 1) {
    throw SuiTransactionVerificationException(
      'redeem_funds: expected 1 type argument, found '
      '${redeemCommand.typeArguments.length}',
    );
  }
  if (redeemCommand.arguments.length != 1) {
    throw SuiTransactionVerificationException(
      'redeem_funds: expected 1 argument, found '
      '${redeemCommand.arguments.length}',
    );
  }
  {
    final arg = redeemCommand.arguments.single;
    if (arg.kind != SuiArgumentKind.input || arg.index != 0) {
      throw SuiTransactionVerificationException(
        'redeem_funds argument does not reference input 0',
      );
    }
  }

  // Command 1: send_funds<T>(result of command 0, input 1).
  final sendCommand = transaction.commands[1];
  if (sendCommand is! SuiMoveCallCommand) {
    throw SuiTransactionVerificationException(
      'Command 1 is not a Move call, found ${sendCommand.label}',
    );
  }
  if (normaliseSuiAddress(sendCommand.package) != _kBalancePackage ||
      sendCommand.module != _kBalanceModule ||
      sendCommand.function != _kSendFundsFunction) {
    throw SuiTransactionVerificationException(
      'Expected $_kBalancePackage::$_kBalanceModule::$_kSendFundsFunction, '
      'found ${sendCommand.target}',
    );
  }
  if (sendCommand.typeArguments.length != 1) {
    throw SuiTransactionVerificationException(
      'send_funds: expected 1 type argument, found '
      '${sendCommand.typeArguments.length}',
    );
  }
  if (sendCommand.arguments.length != 2) {
    throw SuiTransactionVerificationException(
      'send_funds: expected 2 arguments, found '
      '${sendCommand.arguments.length}',
    );
  }
  {
    // First argument must be the result of command 0 (the redeemed balance),
    // not a smuggled-in object; second must be recipient input 1.
    final balanceArg = sendCommand.arguments[0];
    if (balanceArg.kind != SuiArgumentKind.result || balanceArg.index != 0) {
      throw SuiTransactionVerificationException(
        'send_funds first argument does not reference the redeem_funds result',
      );
    }
    final recipientArg = sendCommand.arguments[1];
    if (recipientArg.kind != SuiArgumentKind.input || recipientArg.index != 1) {
      throw SuiTransactionVerificationException(
        'send_funds second argument does not reference input 1',
      );
    }
  }

  // ── Inputs ──
  // Exactly two: the withdrawn balance, then the recipient. Nothing else.
  if (transaction.inputs.length != 2) {
    throw SuiTransactionVerificationException(
      'Expected exactly 2 inputs, found ${transaction.inputs.length}',
    );
  }

  final withdrawal = transaction.inputs[0];
  if (withdrawal is! SuiFundsWithdrawalInput) {
    throw SuiTransactionVerificationException(
      'Input 0 is not a funds withdrawal',
    );
  }

  // The amount. The one value the user chose, and the reason this check exists.
  if (withdrawal.amount != expectation.amountBaseUnits) {
    throw SuiTransactionVerificationException(
      'Amount is ${withdrawal.amount} base units, '
      'expected ${expectation.amountBaseUnits}',
    );
  }
  if (withdrawal.source != SuiWithdrawFrom.sender) {
    throw SuiTransactionVerificationException(
      'Withdrawal source is ${withdrawal.source.name}, expected sender',
    );
  }

  // The withdrawn type and both calls' type argument must agree, or the
  // transfer moves a different asset than it withdraws.
  final coinType = withdrawal.coinType.canonical;
  if (redeemCommand.typeArguments.single.canonical != coinType ||
      sendCommand.typeArguments.single.canonical != coinType) {
    throw SuiTransactionVerificationException(
      'Call type arguments (redeem '
      '${redeemCommand.typeArguments.single.canonical}, send '
      '${sendCommand.typeArguments.single.canonical}) do not both match '
      'withdrawn type $coinType',
    );
  }
  if (expectation.expectedCoinType != null &&
      expectation.expectedCoinType != coinType) {
    throw SuiTransactionVerificationException(
      'Coin type is $coinType, expected ${expectation.expectedCoinType}',
    );
  }

  final recipientInput = transaction.inputs[1];
  if (recipientInput is! SuiPureInput) {
    throw SuiTransactionVerificationException('Input 1 is not an inline value');
  }
  final recipientAddress = recipientInput.asAddress;
  if (recipientAddress == null) {
    throw SuiTransactionVerificationException(
      'Input 1 is ${recipientInput.bytes.length} byte(s), not a 32-byte '
      'address',
    );
  }
  final recipient = normaliseSuiAddress(recipientAddress);
  if (recipient == expectedSender) {
    // The backend rejects this too, but a self-transfer that reached signing
    // would be a sign the resolution step was manipulated.
    throw SuiTransactionVerificationException('Recipient equals the sender');
  }
  if (expectation.expectedRecipient != null &&
      normaliseSuiAddress(expectation.expectedRecipient!) != recipient) {
    throw SuiTransactionVerificationException(
      'Recipient is $recipient, expected '
      '${normaliseSuiAddress(expectation.expectedRecipient!)}',
    );
  }

  // ── Expiration ──
  // Must be the bounded form. `None` would make the signed bytes replayable
  // forever, and a plain `Epoch` bound carries no chain binding.
  final expiration = transaction.expiration;
  if (expiration is! SuiValidDuringExpiration) {
    throw SuiTransactionVerificationException(
      'Expiration is not epoch-bounded',
    );
  }
  if (expiration.minEpoch == null || expiration.maxEpoch == null) {
    throw SuiTransactionVerificationException(
      'Expiration is missing an epoch bound',
    );
  }
  if (expiration.maxEpoch! < expiration.minEpoch!) {
    throw SuiTransactionVerificationException(
      'Expiration max epoch precedes min epoch',
    );
  }
  // Two epochs is the protocol limit. A wider window would mean signed bytes
  // stay replayable longer than the chain requires.
  if (expiration.maxEpoch! - expiration.minEpoch! > BigInt.two) {
    throw SuiTransactionVerificationException(
      'Expiration spans more than two epochs',
    );
  }
  final chain = normaliseSuiAddress(expiration.chain);
  if (expectation.expectedChain != null &&
      normaliseSuiAddress(expectation.expectedChain!) != chain) {
    throw SuiTransactionVerificationException(
      'Chain identifier is $chain, expected '
      '${normaliseSuiAddress(expectation.expectedChain!)}',
    );
  }

  return SuiVerifiedTransfer(
    recipientAddress: recipient,
    amountBaseUnits: withdrawal.amount,
    coinType: coinType,
    chain: chain,
  );
}

/// Converts a UI USDC amount to base units, exactly.
///
/// Goes via the 6-decimal string rather than `(amount * 1e6).round()`: the
/// multiply is done in binary floating point, where a value the user sees as
/// `0.07` is really slightly off and can land a base unit away. Formatting
/// first pins the value to the decimal the user was actually shown, which is
/// the number the verification is supposed to be comparing against.
BigInt usdcBaseUnits(double amountUsdc) {
  if (amountUsdc.isNaN || amountUsdc.isInfinite || amountUsdc < 0) {
    throw SuiTransactionVerificationException(
      'Amount $amountUsdc is not a payable value',
    );
  }
  final fixed = amountUsdc.toStringAsFixed(6);
  final parts = fixed.split('.');
  return BigInt.parse('${parts[0]}${parts[1]}');
}

/// One recipient of a split payment, as the confirm sheet showed it.
class SuiSplitPart {
  const SuiSplitPart({required this.address, required this.amountBaseUnits});
  final String address;
  final BigInt amountBaseUnits;
}

/// Checks a split payment (AppKit splits) before signing: a gasless
/// transaction that pays exactly [parts], in order, from [senderAddress], and
/// does nothing else.
///
/// Shape, per part `i`: input `2i` is a withdrawal of that part's amount from
/// the sender, input `2i+1` its recipient; command `2i` is
/// `0x2::balance::redeem_funds(input 2i)` and command `2i+1` is
/// `0x2::balance::send_funds(result 2i, input 2i+1)`. All of one coin type.
void verifyGaslessUsdcSplit({
  required String transactionDataBcsBase64,
  required String senderAddress,
  required List<SuiSplitPart> parts,
  String? expectedCoinType,
}) {
  void no(String why) => throw SuiTransactionVerificationException(why);
  if (parts.isEmpty || parts.length > 4) no('A split pays 1 to 4 people');
  final Uint8List bytes;
  try {
    bytes = base64.decode(transactionDataBcsBase64.trim());
  } on FormatException catch (error) {
    throw SuiTransactionDecodeException(
      'Transaction payload is not valid base64: ${error.message}',
    );
  }
  final tx = decodeSuiTransaction(bytes);
  final sender = normaliseSuiAddress(tx.sender);
  if (sender != normaliseSuiAddress(senderAddress)) no('Sender is $sender');
  if (!tx.gasPayment.isGasless) no('Transaction is not gasless');
  if (normaliseSuiAddress(tx.gasPayment.owner) != sender) {
    no('Gas owner is not the sender');
  }
  if (tx.commands.length != parts.length * 2) {
    no('Expected ${parts.length * 2} commands, found ${tx.commands.length}');
  }
  if (tx.inputs.length != parts.length * 2) {
    no('Expected ${parts.length * 2} inputs, found ${tx.inputs.length}');
  }
  String? coinType;
  for (var i = 0; i < parts.length; i++) {
    final withdrawal = tx.inputs[2 * i];
    final recipientInput = tx.inputs[2 * i + 1];
    if (withdrawal is! SuiFundsWithdrawalInput) {
      no('Input ${2 * i} is not a withdrawal');
    }
    withdrawal as SuiFundsWithdrawalInput;
    if (withdrawal.source != SuiWithdrawFrom.sender) {
      no('Part $i is not paid by the sender');
    }
    if (withdrawal.amount != parts[i].amountBaseUnits) {
      no(
        'Part $i is ${withdrawal.amount}, expected ${parts[i].amountBaseUnits}',
      );
    }
    final type = withdrawal.coinType.canonical;
    coinType ??= type;
    if (type != coinType) no('Parts withdraw different currencies');
    if (recipientInput is! SuiPureInput || recipientInput.asAddress == null) {
      no('Input ${2 * i + 1} is not an address');
    }
    final recipient = normaliseSuiAddress(
      (recipientInput as SuiPureInput).asAddress!,
    );
    if (recipient != normaliseSuiAddress(parts[i].address)) {
      no('Part $i goes to $recipient');
    }
    if (recipient == sender) no('Part $i pays the sender');

    final redeem = tx.commands[2 * i];
    final send = tx.commands[2 * i + 1];
    if (redeem is! SuiMoveCallCommand || send is! SuiMoveCallCommand) {
      no('Part $i has a non-call step');
    }
    redeem as SuiMoveCallCommand;
    send as SuiMoveCallCommand;
    if (normaliseSuiAddress(redeem.package) != _kBalancePackage ||
        redeem.module != _kBalanceModule ||
        redeem.function != _kRedeemFundsFunction ||
        redeem.typeArguments.length != 1 ||
        redeem.typeArguments.single.canonical != type ||
        redeem.arguments.length != 1 ||
        redeem.arguments.single.kind != SuiArgumentKind.input ||
        redeem.arguments.single.index != 2 * i) {
      no('Part $i: first step is not redeem_funds of its withdrawal');
    }
    if (normaliseSuiAddress(send.package) != _kBalancePackage ||
        send.module != _kBalanceModule ||
        send.function != _kSendFundsFunction ||
        send.typeArguments.length != 1 ||
        send.typeArguments.single.canonical != type ||
        send.arguments.length != 2 ||
        send.arguments[0].kind != SuiArgumentKind.result ||
        send.arguments[0].index != 2 * i ||
        send.arguments[1].kind != SuiArgumentKind.input ||
        send.arguments[1].index != 2 * i + 1) {
      no('Part $i: second step does not send that money to its recipient');
    }
  }
  if (expectedCoinType != null && coinType != expectedCoinType) {
    no('Coin type is $coinType, expected $expectedCoinType');
  }
  final expiration = tx.expiration;
  if (expiration is! SuiValidDuringExpiration ||
      expiration.minEpoch == null ||
      expiration.maxEpoch == null ||
      expiration.maxEpoch! < expiration.minEpoch! ||
      expiration.maxEpoch! - expiration.minEpoch! > BigInt.two) {
    no('Expiration is not a bounded epoch window');
  }
}

// ── Ziro palm pay (contracts.md §1.4) ───────────────────────────────────────
//
// Customer transactions core builds and sponsors for palm pay. Each verifier
// accepts exactly one shape and the values this phone chose (limits, the
// commitment it computed itself, the pause flag), against the package,
// Registry, relayer and coin type it trusts. Anything else throws
// [SuiTransactionVerificationException] and nothing is signed.

const _kStdPackage =
    '0x0000000000000000000000000000000000000000000000000000000000000001';
const _kFrameworkPackage = _kBalancePackage;

/// Name the allowance carries; shown to the customer by the framework.
const kZiroAllowanceName = 'Ziro palm pay';
const _kZiroRatePeriodMs = 86400000;

/// What the phone trusts for every Ziro transaction.
class ZiroTxExpectation {
  ZiroTxExpectation({
    required String sender,
    required String packageId,
    required String registryId,
    required String relayer,
    required this.coinType,
  }) : sender = normaliseSuiAddress(sender),
       packageId = normaliseSuiAddress(packageId),
       registryId = normaliseSuiAddress(registryId),
       relayer = normaliseSuiAddress(relayer);

  /// The customer, who signs.
  final String sender;
  final String packageId;
  final String registryId;
  final String relayer;

  /// Canonical coin type (full 64-hex addresses), e.g. `0x…::usdc::USDC`.
  final String coinType;

  String get balanceType => '$_kFrameworkPackage::balance::Balance<$coinType>';
  String get ziroAppType => '$packageId::ziro::ZIRO';
}

/// Objects a verified Ziro transaction touches, for the caller's own checks.
class ZiroVerifiedTx {
  const ZiroVerifiedTx({this.accountId, this.allowanceId, this.capId});
  final String? accountId;
  final String? allowanceId;
  final String? capId;
}

Never _zno(String why) => throw SuiTransactionVerificationException(why);

SuiDecodedTransaction _ziroDecode(String b64, ZiroTxExpectation e) {
  final Uint8List bytes;
  try {
    bytes = base64.decode(b64.trim());
  } on FormatException catch (error) {
    throw SuiTransactionDecodeException(
      'Transaction payload is not valid base64: ${error.message}',
    );
  }
  final tx = decodeSuiTransaction(bytes);
  if (normaliseSuiAddress(tx.sender) != e.sender) _zno('sender');
  // Sponsored: the gas is someone else's, never the customer's coins.
  if (normaliseSuiAddress(tx.gasPayment.owner) == e.sender) {
    _zno('gas is paid by the customer');
  }
  if (tx.commands.any((c) => c is! SuiMoveCallCommand)) _zno('non-call step');
  if (tx.inputs.any((i) => i is SuiFundsWithdrawalInput)) {
    _zno('takes money from a balance');
  }
  // Every input must be used, and nothing may touch the gas coin.
  final used = <int>{};
  for (final c in tx.commands.cast<SuiMoveCallCommand>()) {
    for (final a in c.arguments) {
      if (a.kind == SuiArgumentKind.gas) _zno('uses the gas coin');
      if (a.kind == SuiArgumentKind.nestedResult) _zno('nested result');
      if (a.kind == SuiArgumentKind.input) used.add(a.index!);
    }
  }
  if (used.length != tx.inputs.length) _zno('unused or missing inputs');
  return tx;
}

SuiInput _zin(SuiDecodedTransaction tx, SuiArgument a) {
  if (a.kind != SuiArgumentKind.input ||
      a.index == null ||
      a.index! >= tx.inputs.length) {
    _zno('argument is not an input');
  }
  return tx.inputs[a.index!];
}

Uint8List _zpure(SuiDecodedTransaction tx, SuiArgument a) {
  final i = _zin(tx, a);
  if (i is! SuiPureInput) _zno('argument is not a plain value');
  return i.bytes;
}

BigInt _zuint(Uint8List b, int width) {
  if (b.length != width) _zno('number has ${b.length} bytes, expected $width');
  var v = BigInt.zero;
  for (var i = width - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(b[i]);
  }
  return v;
}

BigInt _zu64(SuiDecodedTransaction tx, SuiArgument a) => _zuint(_zpure(tx, a), 8);
BigInt _zu256(SuiDecodedTransaction tx, SuiArgument a) =>
    _zuint(_zpure(tx, a), 32);

bool _zbool(SuiDecodedTransaction tx, SuiArgument a) {
  final b = _zpure(tx, a);
  if (b.length != 1 || b[0] > 1) _zno('not a yes/no value');
  return b[0] == 1;
}

String _zaddr(SuiDecodedTransaction tx, SuiArgument a) {
  final i = _zin(tx, a);
  final addr = i is SuiPureInput ? i.asAddress : null;
  if (addr == null) _zno('not an address');
  return normaliseSuiAddress(addr);
}

/// A BCS `vector<u8>` (or `String`): ULEB length, then exactly that many bytes.
Uint8List _zvec(SuiDecodedTransaction tx, SuiArgument a) {
  final r = SuiBcsReader(_zpure(tx, a));
  final v = r.readByteVector();
  r.expectEnd();
  return v;
}

bool _zsame(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

SuiSharedInput _zshared(
  SuiDecodedTransaction tx,
  SuiArgument a, {
  String? id,
  bool? mutable,
}) {
  final i = _zin(tx, a);
  if (i is! SuiSharedInput) _zno('not a shared object');
  if (id != null && normaliseSuiAddress(i.objectId) != id) _zno('wrong object');
  if (mutable != null && i.mutable != mutable) _zno('wrong object access');
  return i;
}

/// Owned or shared object input; returns its ID.
String _zobject(SuiDecodedTransaction tx, SuiArgument a) {
  final i = _zin(tx, a);
  if (i is SuiSharedInput) return normaliseSuiAddress(i.objectId);
  if (i is SuiObjectInput && i.kind == SuiObjectInputKind.immutableOrOwned) {
    return normaliseSuiAddress(i.reference.objectId);
  }
  _zno('not an object');
}

void _zresult(SuiArgument a, int command) {
  if (a.kind != SuiArgumentKind.result || a.index != command) {
    _zno('expected the result of step $command');
  }
}

SuiMoveCallCommand _zcall(
  SuiDecodedTransaction tx,
  int index,
  String package,
  String module,
  String function, {
  List<String> typeArgs = const [],
  required int argc,
}) {
  final c = tx.commands[index] as SuiMoveCallCommand;
  if (normaliseSuiAddress(c.package) != normaliseSuiAddress(package) ||
      c.module != module ||
      c.function != function) {
    _zno('step $index is ${c.target}, expected $module::$function');
  }
  if (c.typeArguments.length != typeArgs.length) _zno('step $index types');
  for (var i = 0; i < typeArgs.length; i++) {
    if (c.typeArguments[i].canonical != typeArgs[i]) {
      _zno('step $index type ${c.typeArguments[i].canonical}');
    }
  }
  if (c.arguments.length != argc) _zno('step $index takes ${c.arguments.length}');
  return c;
}

/// Steps 1–3 of contracts §1.4 enroll, starting at command [k]: the daily
/// rate limit, `option::some`, and `propose_for_app` naming the relayer as
/// spender with an expiry about a year out.
void _zproposal(
  SuiDecodedTransaction tx,
  int k,
  ZiroTxExpectation e, {
  required BigInt dailyMax,
  required DateTime now,
}) {
  final rate = _zcall(
    tx,
    k,
    _kFrameworkPackage,
    'allowance',
    'periodic_rate_limit',
    argc: 2,
  );
  if (_zu64(tx, rate.arguments[0]) != BigInt.from(_kZiroRatePeriodMs)) {
    _zno('rate period');
  }
  if (_zu256(tx, rate.arguments[1]) != dailyMax) _zno('daily maximum');

  final some = _zcall(
    tx,
    k + 1,
    _kStdPackage,
    'option',
    'some',
    typeArgs: ['$_kFrameworkPackage::allowance::RateLimit'],
    argc: 1,
  );
  _zresult(some.arguments[0], k);

  final p = _zcall(
    tx,
    k + 2,
    _kFrameworkPackage,
    'allowance',
    'propose_for_app',
    typeArgs: [e.balanceType, e.ziroAppType],
    argc: 6,
  );
  if (!_zsame(_zvec(tx, p.arguments[0]), utf8.encode(kZiroAllowanceName))) {
    _zno('allowance name');
  }
  if (_zaddr(tx, p.arguments[1]) != e.relayer) _zno('spender is not Ziro');
  // none<u256>: no total cap. none<u64>: no start time.
  if (!_zsame(_zpure(tx, p.arguments[2]), const [0])) _zno('total cap');
  if (!_zsame(_zpure(tx, p.arguments[3]), const [0])) _zno('start time');
  final exp = _zpure(tx, p.arguments[4]);
  if (exp.length != 9 || exp[0] != 1) _zno('expiry');
  final expiryMs = _zuint(Uint8List.sublistView(exp, 1), 8);
  final nowMs = BigInt.from(now.millisecondsSinceEpoch);
  const day = 86400000;
  if (expiryMs < nowMs + BigInt.from(364 * day) ||
      expiryMs > nowMs + BigInt.from(366 * day)) {
    _zno('expiry is not about a year out');
  }
  _zresult(p.arguments[5], k + 1);
}

void _zlimits(BigInt per, BigInt noPin) {
  if (noPin > per) _zno('no-PIN amount is above the per-payment maximum');
}

/// Enroll: rate limit, `some`, `propose_for_app`, then
/// `ziro::open_account<USDC>(proposal, Registry, commitment, per, no_pin)`.
ZiroVerifiedTx verifyZiroEnroll(
  String txB64, {
  required ZiroTxExpectation expectation,
  required BigInt perPaymentMax,
  required BigInt noPinMax,
  required BigInt dailyMax,
  required List<int> commitment,
  DateTime? now,
}) {
  final e = expectation;
  final tx = _ziroDecode(txB64, e);
  if (tx.commands.length != 4) _zno('expected 4 steps');
  _zlimits(perPaymentMax, noPinMax);
  _zproposal(tx, 0, e, dailyMax: dailyMax, now: now ?? DateTime.now());
  final open = _zcall(
    tx,
    3,
    e.packageId,
    'ziro',
    'open_account',
    typeArgs: [e.coinType],
    argc: 5,
  );
  _zresult(open.arguments[0], 2);
  _zshared(tx, open.arguments[1], id: e.registryId);
  if (commitment.length != 32 || !_zsame(_zvec(tx, open.arguments[2]), commitment)) {
    _zno('commitment');
  }
  if (_zu64(tx, open.arguments[3]) != perPaymentMax) _zno('per-payment maximum');
  if (_zu64(tx, open.arguments[4]) != noPinMax) _zno('no-PIN amount');
  return const ZiroVerifiedTx();
}

/// Limits: `ziro::set_limits(acct, per, no_pin)` when the daily maximum is
/// unchanged; otherwise `allowance::revoke` + steps 1–3 +
/// `ziro::reissue_allowance<USDC>(acct, proposal, Registry, per, no_pin)`.
ZiroVerifiedTx verifyZiroLimits(
  String txB64, {
  required ZiroTxExpectation expectation,
  required BigInt perPaymentMax,
  required BigInt noPinMax,
  required BigInt dailyMax,
  required BigInt currentDailyMax,
  DateTime? now,
}) {
  final e = expectation;
  final tx = _ziroDecode(txB64, e);
  _zlimits(perPaymentMax, noPinMax);
  if (tx.commands.length == 1) {
    if (dailyMax != currentDailyMax) _zno('daily maximum not changed');
    final c = _zcall(tx, 0, e.packageId, 'ziro', 'set_limits', argc: 3);
    final acct = _zshared(tx, c.arguments[0], mutable: true);
    if (_zu64(tx, c.arguments[1]) != perPaymentMax) _zno('per-payment maximum');
    if (_zu64(tx, c.arguments[2]) != noPinMax) _zno('no-PIN amount');
    return ZiroVerifiedTx(accountId: normaliseSuiAddress(acct.objectId));
  }
  if (tx.commands.length != 5) _zno('expected 1 or 5 steps');
  final revoke = _zcall(
    tx,
    0,
    _kFrameworkPackage,
    'allowance',
    'revoke',
    typeArgs: [e.balanceType],
    argc: 2,
  );
  final cap = _zobject(tx, revoke.arguments[0]);
  final old = _zobject(tx, revoke.arguments[1]);
  _zproposal(tx, 1, e, dailyMax: dailyMax, now: now ?? DateTime.now());
  final re = _zcall(
    tx,
    4,
    e.packageId,
    'ziro',
    'reissue_allowance',
    typeArgs: [e.coinType],
    argc: 5,
  );
  final acct = _zshared(tx, re.arguments[0], mutable: true);
  _zresult(re.arguments[1], 3);
  _zshared(tx, re.arguments[2], id: e.registryId);
  if (_zu64(tx, re.arguments[3]) != perPaymentMax) _zno('per-payment maximum');
  if (_zu64(tx, re.arguments[4]) != noPinMax) _zno('no-PIN amount');
  return ZiroVerifiedTx(
    accountId: normaliseSuiAddress(acct.objectId),
    allowanceId: old,
    capId: cap,
  );
}

/// PIN change and re-enrollment: `ziro::set_commitment(acct, commitment)`.
ZiroVerifiedTx verifyZiroCommitment(
  String txB64, {
  required ZiroTxExpectation expectation,
  required List<int> commitment,
}) {
  final e = expectation;
  final tx = _ziroDecode(txB64, e);
  if (tx.commands.length != 1) _zno('expected 1 step');
  final c = _zcall(tx, 0, e.packageId, 'ziro', 'set_commitment', argc: 2);
  final acct = _zshared(tx, c.arguments[0], mutable: true);
  if (commitment.length != 32 || !_zsame(_zvec(tx, c.arguments[1]), commitment)) {
    _zno('commitment');
  }
  return ZiroVerifiedTx(accountId: normaliseSuiAddress(acct.objectId));
}

/// Pause, resume and "Wasn't me": `ziro::set_account_paused(acct, paused)`.
ZiroVerifiedTx verifyZiroPause(
  String txB64, {
  required ZiroTxExpectation expectation,
  required bool paused,
}) {
  final e = expectation;
  final tx = _ziroDecode(txB64, e);
  if (tx.commands.length != 1) _zno('expected 1 step');
  final c = _zcall(tx, 0, e.packageId, 'ziro', 'set_account_paused', argc: 2);
  final acct = _zshared(tx, c.arguments[0], mutable: true);
  if (_zbool(tx, c.arguments[1]) != paused) _zno('pause flag');
  return ZiroVerifiedTx(accountId: normaliseSuiAddress(acct.objectId));
}

/// Delete: `allowance::revoke<Balance<USDC>>(cap, allowance)` then
/// `ziro::close_account(acct)`.
ZiroVerifiedTx verifyZiroDelete(
  String txB64, {
  required ZiroTxExpectation expectation,
}) {
  final e = expectation;
  final tx = _ziroDecode(txB64, e);
  if (tx.commands.length != 2) _zno('expected 2 steps');
  final revoke = _zcall(
    tx,
    0,
    _kFrameworkPackage,
    'allowance',
    'revoke',
    typeArgs: [e.balanceType],
    argc: 2,
  );
  final cap = _zobject(tx, revoke.arguments[0]);
  final allowance = _zobject(tx, revoke.arguments[1]);
  final close = _zcall(tx, 1, e.packageId, 'ziro', 'close_account', argc: 1);
  final acct = _zshared(tx, close.arguments[0], mutable: true);
  if (normaliseSuiAddress(acct.objectId) == allowance ||
      normaliseSuiAddress(acct.objectId) == cap) {
    _zno('same object twice');
  }
  return ZiroVerifiedTx(
    accountId: normaliseSuiAddress(acct.objectId),
    allowanceId: allowance,
    capId: cap,
  );
}
