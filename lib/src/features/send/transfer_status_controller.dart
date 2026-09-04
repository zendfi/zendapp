import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../models/api_exceptions.dart'
    show ApiException, PinDecryptionException, RequestTimeoutException;
import '../../services/payment_rails.dart' show RailUnavailableException;
import '../../services/sound_service.dart';
import '../../services/wallet_session_cache.dart';
import '../request/payment_request.dart';

/// How this account is allowed to authorise a transfer of a given amount.
///
/// This is the *preflight* — it answers "can this be sent without asking
/// the user for anything?" before any sheet is dismissed, which is what
/// lets the fast path close the sheet immediately and hand off to a
/// banner. It deliberately contains no UI and never prompts.
enum TransferAuthMode {
  /// zkLogin account: signing authority is an in-memory ephemeral key plus
  /// a proof. There is no local keypair and no PIN, so a PIN prompt would
  /// be unsatisfiable. Step-up for large amounts is a Google
  /// re-authentication, handled inside the transfer call itself.
  zkLogin,

  /// A warm session keypair is cached and policy doesn't require a PIN for
  /// this amount — send straight away.
  session,

  /// Policy requires a PIN (per-payment setting on, or amount at/above the
  /// threshold — default $500, default-on), or there's no session keypair
  /// to sign with. There is input to collect, so the fast path does not
  /// apply and the full send sheet must handle it.
  pinRequired,
}

@immutable
class TransferAuth {
  const TransferAuth._(this.mode, this.keypairBytes);

  /// Builds a decision directly, bypassing [resolve].
  ///
  /// Tests need this because [resolve] reads secure storage, which has no
  /// implementation under `flutter_test` — without a seam here, the entire
  /// send path would be unreachable from a test.
  @visibleForTesting
  const TransferAuth.forTest(this.mode, [this.keypairBytes]);

  final TransferAuthMode mode;
  final dynamic keypairBytes;

  bool get needsPin => mode == TransferAuthMode.pinRequired;

  /// Mirrors the decision tree in `_SendFlowSheetState._proceedFromRecipient`
  /// so both paths agree on when a PIN is required. Reads only — safe to
  /// call before deciding whether to dismiss a sheet.
  static Future<TransferAuth> resolve(ZendAppModel model, double amount) async {
    if (await model.authService.isZkLoginAccount()) {
      return const TransferAuth._(TransferAuthMode.zkLogin, null);
    }
    final needsPin = await model.signingPolicyService.requiresPinForAmount(amount);
    final cache = WalletSessionCache.instance;
    if (!needsPin && cache.hasKeypair) {
      return TransferAuth._(TransferAuthMode.session, cache.keypair);
    }
    return const TransferAuth._(TransferAuthMode.pinRequired, null);
  }
}

enum TransferStatusKind {
  /// In flight. Auto-dismisses only by resolving into one of the below.
  sending,

  /// Confirmed sent.
  sent,

  /// Payment request created.
  requested,

  /// Definite failure. Never auto-dismisses — see [TransferStatusController].
  failed,

  /// The server never answered, so we genuinely don't know whether it
  /// landed (spec §16). Never presented as a failure.
  uncertain,
}

/// An immutable snapshot of what the transfer banner should be saying.
@immutable
class TransferStatus {
  const TransferStatus({
    required this.kind,
    required this.amount,
    required this.actionId,
    this.recipientZendtag,
    this.recipientEmail,
    this.recipientDisplayName,
    this.note,
    this.message,
    this.canRetry = false,
    this.request,
  });

  /// Identifies the user action this status belongs to, stable across the
  /// whole `sending → sent/failed/uncertain` lifecycle of one send.
  ///
  /// The banner keys on this so a status change *mutates the existing
  /// banner in place* rather than tearing it down and replaying the
  /// slide-in — one event resolving, not two events. A genuinely new send
  /// gets a new id and does replay the entrance.
  final int actionId;

  final TransferStatusKind kind;
  final double amount;
  final String? recipientZendtag;
  final String? recipientEmail;
  final String? recipientDisplayName;
  final String? note;

  /// Failure copy. Only meaningful for [TransferStatusKind.failed] and
  /// [TransferStatusKind.uncertain].
  final String? message;

  final bool canRetry;

  /// The created request, for [TransferStatusKind.requested] — carried so
  /// the banner can offer a QR shortcut without refetching.
  final PaymentRequest? request;

  /// True for the request flow, in any state — including `failed`.
  ///
  /// Keyed off [request] being non-null rather than off [kind], because
  /// [kind] can't distinguish a failed request from a failed send, and the
  /// two need different copy ("Couldn't request … from" vs "Couldn't send …
  /// to") *and* different retries. Only the request path ever sets
  /// [request]: a placeholder while in flight, the real one once created.
  bool get isRequest => request != null;

  String get amountLabel => amount == amount.roundToDouble()
      ? '\$${amount.toStringAsFixed(0)}'
      : '\$${amount.toStringAsFixed(2)}';

  /// "@omooba", or the email for a non-Zend recipient.
  String get recipientLabel {
    if (recipientZendtag != null && recipientZendtag!.isNotEmpty) {
      return '@$recipientZendtag';
    }
    return recipientEmail ?? 'them';
  }

  TransferStatus copyWith({
    TransferStatusKind? kind,
    String? message,
    bool? canRetry,
    PaymentRequest? request,
  }) {
    return TransferStatus(
      kind: kind ?? this.kind,
      amount: amount,
      actionId: actionId,
      recipientZendtag: recipientZendtag,
      recipientEmail: recipientEmail,
      recipientDisplayName: recipientDisplayName,
      note: note,
      message: message ?? this.message,
      canRetry: canRetry ?? this.canRetry,
      request: request ?? this.request,
    );
  }
}

/// App-scoped owner of send/request execution and its user-visible status.
///
/// ── Why this isn't in the sheet ────────────────────────────────────────
/// The point of the instant flow is that the sheet closes the moment the
/// user commits, so the payment feels immediate. That makes it impossible
/// for the sheet's `State` to own the outcome: it's disposed while the
/// transfer is still in flight. In particular [_resolveUncertainTransfer]
/// polls transfer history for up to 18 seconds, which is far longer than
/// the sheet lives. Anything owned by the sheet would be torn down
/// mid-flight and an uncertain transfer would become a silent unknown.
///
/// So execution, failure and uncertainty all live here, above the
/// navigator, and the banner is just a view of [status].
///
/// ── Failure is never silent ────────────────────────────────────────────
/// Optimistic UI is only honest if the failure path is as loud as the
/// success path. Two rules enforce that:
///
///   * `failed` and `uncertain` never auto-dismiss. The user dismisses
///     them, or acts on them.
///   * If an older in-flight transfer resolves while a newer banner is
///     showing, a *success* is dropped (the newer status is more relevant,
///     and balance/history still refresh) but a *failure* always takes
///     over the banner. Losing money quietly is not an acceptable
///     trade for tidy banner semantics.
class TransferStatusController extends ChangeNotifier {
  TransferStatusController({required ZendAppModel model}) : _model = model;

  final ZendAppModel _model;

  /// How long a confirmed send stays on screen. Long enough to register,
  /// short enough to stay out of the way.
  static const Duration sentLinger = Duration(seconds: 4);

  /// Requests linger longer than sends because the banner carries a QR
  /// shortcut the user may want to act on.
  static const Duration requestedLinger = Duration(seconds: 8);

  TransferStatus? _status;
  TransferStatus? get status => _status;

  Timer? _autoDismiss;

  /// Incremented per user-initiated action. Used to decide whether a
  /// late-resolving transfer still owns the banner.
  int _generation = 0;

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  void dismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    _status = null;
    notifyListeners();
  }

  void _set(TransferStatus status, {Duration? linger}) {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    _status = status;
    if (linger != null) {
      _autoDismiss = Timer(linger, dismiss);
    }
    notifyListeners();
  }

  /// True when [gen] is still the action the banner belongs to.
  bool _owns(int gen) => gen == _generation;

  /// Surfaces a terminal failure. Deliberately ignores [_owns]: a failure
  /// takes over the banner even if a newer action has started since, per
  /// the class doc. [pending] carries the *failing* action's own details,
  /// so the banner names the right amount and recipient rather than
  /// whatever happens to be on screen.
  void _fail(
    TransferStatus pending,
    String message, {
    bool canRetry = true,
  }) {
    _set(pending.copyWith(
      kind: TransferStatusKind.failed,
      message: message,
      canRetry: canRetry,
    ));
  }

  // ── Send ────────────────────────────────────────────────────────────────

  /// Executes a pin-less transfer, driving the banner from `sending` to
  /// `sent` / `failed` / `uncertain`.
  ///
  /// Only ever called with a [TransferAuth] of
  /// [TransferAuthMode.session] or [TransferAuthMode.zkLogin]. The
  /// PIN-required path keeps its heavier in-sheet treatment, because there
  /// is input to collect and the sheet can't be closed first.
  Future<void> send({
    required double amount,
    required String recipientZendtag,
    required TransferAuth auth,
    String? recipientDisplayName,
    String? note,
  }) async {
    assert(!auth.needsPin, 'PIN-required sends must stay in the send sheet');
    final gen = ++_generation;

    final pending = TransferStatus(
      kind: TransferStatusKind.sending,
      amount: amount,
      actionId: gen,
      recipientZendtag: recipientZendtag,
      recipientDisplayName: recipientDisplayName,
      note: note,
    );
    _set(pending);

    try {
      await _submit(
        recipientZendtag: recipientZendtag,
        amount: amount,
        note: note,
        keypairBytes: auth.keypairBytes,
      );

      await _model.recordTransfer(
        recipientZendtag: recipientZendtag,
        recipientDisplayName: recipientDisplayName ?? '?',
        amount: amount,
        note: note,
      );
      unawaited(_model.fetchBalance());
      unawaited(_model.fetchHistory());

      if (_owns(gen)) {
        _set(pending.copyWith(kind: TransferStatusKind.sent), linger: sentLinger);
      }
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
    } on RequestTimeoutException {
      // Spec §16: the server never responded, so we don't know if this
      // landed. Never guess "failed" — resolve it against the account's
      // own history instead of trusting the absence of a response.
      _set(pending.copyWith(
        kind: TransferStatusKind.uncertain,
        message: "Still confirming this one — we'll update you.",
      ));
      await _resolveUncertain(gen, pending);
    } on RailUnavailableException catch (e) {
      _fail(pending, e.userMessage);
    } on ApiException catch (e) {
      _fail(pending, e.userMessage);
    } on PinDecryptionException {
      // Shouldn't be reachable — this path never passes a raw PIN. If the
      // cached keypair is somehow unusable, retrying won't help.
      _fail(pending, "We couldn't unlock your wallet to sign this.", canRetry: false);
    } catch (_) {
      _fail(pending, "Couldn't complete that. Try again.");
    }
  }

  /// The transfer call itself, including the one legitimate retry.
  Future<void> _submit({
    required String recipientZendtag,
    required double amount,
    required String? note,
    required dynamic keypairBytes,
  }) async {
    try {
      await _model.transferService.sendTransfer(
        recipientZendtag: recipientZendtag,
        amountUsdc: amount,
        pin: null,
        keypairBytes: keypairBytes,
        note: note,
      );
    } on ApiException catch (e) {
      // The backend refuses large transfers from a PIN-less account until
      // Google has re-verified the person. Satisfy that and retry exactly
      // once. Safe to retry: the check runs before anything is broadcast,
      // so nothing was submitted, and a retry takes a fresh idempotency key.
      if (e.errorCode != 'STEP_UP_REQUIRED') rethrow;
      await _model.zkLoginService.satisfyStepUp();
      await _model.transferService.sendTransfer(
        recipientZendtag: recipientZendtag,
        amountUsdc: amount,
        pin: null,
        keypairBytes: keypairBytes,
        note: note,
      );
    }
  }

  /// Resolves an uncertain transfer by polling the account's own transfer
  /// history for a matching, recent entry — the same signal
  /// [ZendAppModel.fetchHistory] already treats as ground truth for the
  /// Feed and Wallet. No transfer-status-by-idempotency-key endpoint
  /// exists on the backend today; this is the closest honest signal
  /// reachable from the client without inventing an API contract for one
  /// edge case.
  ///
  /// Polls rather than checking once: the transfer may still be in
  /// backend-side flight when the client's own request timed out, so a
  /// single immediate check can't tell "not there yet" from "never
  /// happened". Bounded, so it terminates rather than polling forever.
  Future<void> _resolveUncertain(int gen, TransferStatus pending) async {
    const maxAttempts = 6;
    const interval = Duration(seconds: 3);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(interval);
      try {
        await _model.fetchHistory();
      } catch (_) {
        continue; // Network still down — keep trying within the window.
      }

      final found = _model.recentTransactions.any((tx) {
        final entry = tx.entry;
        if (entry == null) return false;
        final matchesRecipient = entry.recipientZendtag.toLowerCase() ==
            pending.recipientZendtag?.toLowerCase();
        final entryAmount = double.tryParse(entry.amountUsdc) ?? -1;
        final matchesAmount = (entryAmount - pending.amount).abs() < 0.005;
        final isRecent =
            DateTime.now().difference(entry.createdAt) < const Duration(minutes: 5);
        return matchesRecipient && matchesAmount && isRecent;
      });

      if (found) {
        await _model.recordTransfer(
          recipientZendtag: pending.recipientZendtag!,
          recipientDisplayName: pending.recipientDisplayName ?? '?',
          amount: pending.amount,
          note: pending.note,
        );
        unawaited(_model.fetchBalance());
        if (_owns(gen)) {
          _set(pending.copyWith(kind: TransferStatusKind.sent), linger: sentLinger);
        }
        HapticFeedback.mediumImpact();
        unawaited(SoundService.playZentSuccess());
        return;
      }
    }

    // Unresolved after the window. Keep the wording honest — we don't know
    // it failed, only that we couldn't confirm it succeeded — so retrying
    // is not offered here. Sending again could double-pay.
    _fail(
      pending,
      "We still can't confirm this went through. Check Activity before sending again.",
      canRetry: false,
    );
  }

  // ── Request ─────────────────────────────────────────────────────────────

  /// Creates a payment request, driving the banner from `sending` to
  /// `requested` / `failed`.
  ///
  /// Requests are reversible — cancelling one costs nothing — which is why
  /// they never get a confirm step and go straight through on one tap.
  Future<void> request({
    required double amount,
    String? recipientZendtag,
    String? recipientEmail,
    String? recipientDisplayName,
    String? note,
  }) async {
    final gen = ++_generation;

    // A placeholder request marks this as the request variant while in
    // flight, so the banner says "Requesting" rather than "Sending".
    final pending = TransferStatus(
      kind: TransferStatusKind.sending,
      amount: amount,
      actionId: gen,
      recipientZendtag: recipientZendtag,
      recipientEmail: recipientEmail,
      recipientDisplayName: recipientDisplayName,
      note: note,
      request: _requestPlaceholder,
    );
    _set(pending);

    try {
      final response = await _model.walletService.apiClient.createPaymentRequest(
        amountUsdc: amount,
        description: note,
        expiresAt: null,
        recipientZendtag: recipientZendtag,
        recipientEmail: recipientEmail,
      );
      final created = PaymentRequest(
        id: response['id'] as String,
        link: response['link_url'] as String,
        amount: (response['amount_usdc'] as num?)?.toDouble() ?? amount,
        description: note ?? '',
        createdAt: DateTime.now(),
        status: PaymentRequestStatus.pending,
        recipientZendtag: response['recipient_zendtag'] as String? ?? recipientZendtag,
        recipientEmail: response['recipient_email'] as String? ?? recipientEmail,
      );
      _model.addPaymentRequest(created);

      if (_owns(gen)) {
        _set(
          pending.copyWith(kind: TransferStatusKind.requested, request: created),
          linger: requestedLinger,
        );
      }
      HapticFeedback.lightImpact();
    } on ApiException catch (e) {
      _fail(pending, e.userMessage);
    } catch (_) {
      _fail(pending, "Couldn't create that request. Try again.");
    }
  }

  /// Stand-in used only to tag an in-flight request as a request rather
  /// than a send. Never surfaced — replaced by the real request on
  /// success, and the banner only reads a request's fields once the status
  /// is [TransferStatusKind.requested].
  static final PaymentRequest _requestPlaceholder = PaymentRequest(
    id: '',
    link: '',
    amount: 0,
    description: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    status: PaymentRequestStatus.pending,
  );
}
