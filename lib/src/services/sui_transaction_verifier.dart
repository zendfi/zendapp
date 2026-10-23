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
///   * there is exactly one command, a call to `0x2::balance::send_funds`,
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
  // Exactly one. This is the check that stops a second command being appended
  // to an otherwise correct transfer.
  if (transaction.commands.length != 1) {
    throw SuiTransactionVerificationException(
      'Expected exactly 1 command, found ${transaction.commands.length}: '
      '${transaction.commands.map((c) => c.label).join(', ')}',
    );
  }
  final command = transaction.commands.single;
  if (command is! SuiMoveCallCommand) {
    throw SuiTransactionVerificationException(
      'Expected a Move call, found ${command.label}',
    );
  }
  if (normaliseSuiAddress(command.package) != _kBalancePackage ||
      command.module != _kBalanceModule ||
      command.function != _kSendFundsFunction) {
    throw SuiTransactionVerificationException(
      'Expected $_kBalancePackage::$_kBalanceModule::$_kSendFundsFunction, '
      'found ${command.target}',
    );
  }
  if (command.typeArguments.length != 1) {
    throw SuiTransactionVerificationException(
      'Expected 1 type argument, found ${command.typeArguments.length}',
    );
  }

  // ── Inputs ──
  // Exactly two, in the order the call takes them: the withdrawn balance, then
  // the recipient.
  if (transaction.inputs.length != 2) {
    throw SuiTransactionVerificationException(
      'Expected exactly 2 inputs, found ${transaction.inputs.length}',
    );
  }
  if (command.arguments.length != 2) {
    throw SuiTransactionVerificationException(
      'Expected 2 call arguments, found ${command.arguments.length}',
    );
  }
  for (var i = 0; i < 2; i++) {
    final argument = command.arguments[i];
    if (argument.kind != SuiArgumentKind.input || argument.index != i) {
      throw SuiTransactionVerificationException(
        'Call argument $i does not reference input $i',
      );
    }
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

  // The withdrawn type and the call's type argument must agree, or the
  // transfer moves a different asset than it withdraws.
  final coinType = withdrawal.coinType.canonical;
  if (command.typeArguments.single.canonical != coinType) {
    throw SuiTransactionVerificationException(
      'Call type argument ${command.typeArguments.single.canonical} '
      'does not match withdrawn type $coinType',
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
    throw SuiTransactionVerificationException(
      'Input 1 is not an inline value',
    );
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
    throw SuiTransactionVerificationException(
      'Recipient equals the sender',
    );
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
