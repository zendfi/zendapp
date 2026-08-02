import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/drop_models.dart';
import '../../services/ble_scanner_service.dart';
import '../../services/drop_discoverability_service.dart';
import '../../services/drop_service.dart';
import '../../services/signing_policy_service.dart';
import '../../services/sound_service.dart';
import '../../services/wallet_session_cache.dart';
import 'drop_confirm_stage.dart';
import 'drop_countdown_stage.dart';
import 'drop_debug_log.dart';
import 'drop_disambiguate_stage.dart';
import 'drop_preview_stage.dart';
import 'drop_processing_stage.dart';
import 'drop_scanner_stage.dart';
import 'drop_success_stage.dart';
import '../send/send_shared_widgets.dart';
import 'package:solar_icons/solar_icons.dart';

enum DropStage {
  scanning,
  preview,       // unconfirmed — preview arrived, GATT still in flight
  confirmed,     // GATT verified — proceed to tier routing (transient)
  disambiguate,  // 2+ confirmed receivers within signal range — user picks one
  countdown,     // Tier 1 (≤$50): 2-second auto-execute
  confirm,       // Tier 2 ($51–$500): confirm button
  biometric,     // Tier 3 ($501–$10,000): confirm + biometric
  pin,           // PIN required — session cache empty or policy requires PIN
  processing,
  success,
  error,
}

/// Shows the Drop bottom sheet modal.
///
/// [amount] is the USDC amount to drop, validated by the send screen.
Future<void> showDropSheet(BuildContext context, {required double amount}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => DropSheet(amount: amount),
  );
}

class DropSheet extends StatefulWidget {
  const DropSheet({super.key, required this.amount});

  final double amount;

  @override
  State<DropSheet> createState() => _DropSheetState();
}

class _DropSheetState extends State<DropSheet>
    with SingleTickerProviderStateMixin {
  static const Duration _stageTransition = Duration(milliseconds: 180);
  static const Duration _sheetResize = Duration(milliseconds: 220);

  DropStage _stage = DropStage.scanning;

  late final BleScannerService _bleScannerService;
  late final DropService _dropService;

  StreamSubscription<List<DiscoveredReceiver>>? _scanSub;
  StreamSubscription<BleScanError>? _scanErrorSub;

  DiscoveredReceiver? _confirmedReceiver;
  List<DiscoveredReceiver> _candidates = []; // for disambiguation
  String? _errorMessage;
  // Nonces that have already been used or rejected by the server — prevent
  // re-sending the same nonce if the BLE scan still returns the stale beacon.
  final Set<String> _exhaustedNonces = {};

  // ── PIN entry state ──────────────────────────────────────────────────────
  // Reached whenever the session cache is empty or SigningPolicyService
  // requires a PIN for this amount — the tier confirmation stages
  // (countdown/confirm/biometric) are a UX gate, not an authentication gate,
  // so they route here via _startSigning() rather than signing directly.
  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  // RSSI gap threshold: if top device is this many dBm stronger than second,
  // auto-select without showing the disambiguation list.
  static const int _kAutoSelectRssiGap = 8;

  // Timeout: if we're stuck in preview (GATT in-flight) for more than this
  // duration, reset back to scanning. Handles the case where GATT fails
  // silently (e.g. both devices scanning simultaneously — nonce race).
  Timer? _previewTimeoutTimer;
  static const Duration _kPreviewTimeout = Duration(seconds: 8);

  // ── Debug panel visibility ────────────────────────────────────────────────
  bool _showDebugPanel = false;

  // ── Note field state ──────────────────────────────────────────────────────
  final _noteController = TextEditingController();
  bool _noteExpanded = false;

  // ── Discoverability restore ──────────────────────────────────────────────
  // Cached at initState so dispose() (where ZendScope.of/.read on a
  // possibly-defunct element is riskier) never needs to touch context.
  // See _onReceiverConfirmed/_resumeDiscoverability/_returnToScanning/_dismiss.
  late final DropDiscoverabilityService _discoverabilityService;
  bool _discoverabilityPaused = false;

  @override
  void initState() {
    super.initState();
    // One-shot read — ZendScope.of() throws in debug builds when called
    // before initState() completes.
    final model = ZendScope.read(context);
    _discoverabilityService = model.dropDiscoverabilityService;
    _dropService = DropService(
      apiClient: model.walletService.apiClient,
      walletService: model.walletService,
    );
    _bleScannerService = BleScannerService(
      apiClient: model.walletService.apiClient,
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticOut,
    ));
    DropDebugLog.i.clear(); // Fresh log for each Drop session
    DropDebugLog.i.add('SHEET', 'Drop sheet opened — amount=\$${widget.amount.toStringAsFixed(2)}');
    _checkBluetoothAndStart();
  }

  @override
  void dispose() {
    // Catch-all: if the sheet is torn down through some path that didn't
    // already call _resumeDiscoverability() (e.g. the route is popped by an
    // ancestor navigator rather than this widget's own _dismiss()), make sure
    // "Be Discoverable" doesn't stay stuck paused.
    _resumeDiscoverability();
    _previewTimeoutTimer?.cancel();
    _scanSub?.cancel();
    _scanErrorSub?.cancel();
    _bleScannerService.stopScan();
    _bleScannerService.dispose();
    _noteController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  // ── BLE lifecycle ─────────────────────────────────────────────────────────

  void _startScanning() {
    _bleScannerService.startScan();
    _scanSub = _bleScannerService.discoveredReceivers.listen(_onReceivers);
    // Previously scan-level failures (the platform scan stream erroring, or
    // startScan() throwing) only reached DropDebugLog — a debug-only ring
    // buffer — so a real user saw the scanning ripple animation spin
    // forever with no way to know discovery had actually stopped working.
    _scanErrorSub = _bleScannerService.errors.listen(_onScanError);
  }

  void _onScanError(BleScanError error) {
    if (!mounted) return;
    if (_stage == DropStage.processing ||
        _stage == DropStage.success ||
        _stage == DropStage.error) {
      return;
    }
    setState(() {
      _errorMessage = error.message;
      _stage = DropStage.error;
    });
  }

  /// Check Bluetooth state before starting, prompt user if it's off.
  Future<void> _checkBluetoothAndStart() async {
    DropDebugLog.i.add('BT', 'Checking Bluetooth adapter state…');

    BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
    try {
      adapterState = await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on ||
                        s == BluetoothAdapterState.off)
          .first
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => FlutterBluePlus.adapterStateNow,
          );
    } catch (e) {
      DropDebugLog.i.add('BT', 'adapterState error: $e — attempting to continue', level: DropLogLevel.warn);
      // SecurityException means BLUETOOTH permission missing at manifest level
      // (Android ≤ 11). The new manifest fixes this — optimistically continue.
      adapterState = BluetoothAdapterState.on;
    }

    DropDebugLog.i.add('BT', 'Stable adapter state: $adapterState');
    if (!mounted) return;

    if (adapterState != BluetoothAdapterState.on) {
      DropDebugLog.i.add('BT', 'Bluetooth is OFF — cannot proceed', level: DropLogLevel.error);
      setState(() {
        _errorMessage = 'Bluetooth is off. Please enable Bluetooth to use Drop.';
        _stage = DropStage.error;
      });
      return;
    }

    DropDebugLog.i.add('BT', 'BLE ready — starting scan (sender mode). Receiver advertises via background service.');
    _startScanning();
    // Sender does NOT advertise — they scan only.
    // The receiver's beacon is broadcast by the Android ForegroundService
    // (DropAdvertiserService) which runs independently of the Drop sheet.
  }

  /// Generate a beacon and start advertising so this device is discoverable
  /// by other nearby Zend users who have Drop open.
  /// NOTE: This is no longer called from the Drop sheet. Advertising is now
  /// managed entirely by DropDiscoverabilityService (profile toggle).
  /// Kept as a no-op comment placeholder to avoid merge conflicts.

  void _onReceivers(List<DiscoveredReceiver> receivers) {
    if (!mounted) return;

    if (_stage == DropStage.processing ||
        _stage == DropStage.success ||
        _stage == DropStage.error) {
      return;
    }

    if (receivers.isEmpty) return;

    final confirmedList = receivers.where((r) => r.isConfirmed).toList();

    if (confirmedList.isNotEmpty) {
      // Only route once — don't re-trigger if already in a tier stage.
      if (_stage != DropStage.scanning &&
          _stage != DropStage.preview &&
          _stage != DropStage.confirmed &&
          _stage != DropStage.disambiguate) {
        return;
      }

      if (confirmedList.length == 1) {
        // Single confirmed receiver — auto-select immediately.
        _onReceiverConfirmed(confirmedList.first);
        return;
      }

      // Multiple confirmed receivers — check if the top one is dominant.
      final best = confirmedList.first;
      final second = confirmedList[1];
      final gap = best.rssi - second.rssi; // positive = best is stronger

      if (gap >= _kAutoSelectRssiGap) {
        // Top device is clearly closest — auto-select silently.
        DropDebugLog.i.add('SHEET',
            'Auto-selecting @${best.gattPayload?.zendtag} (RSSI gap=${gap}dBm > ${_kAutoSelectRssiGap}dBm threshold)',
            level: DropLogLevel.ok);
        _onReceiverConfirmed(best);
      } else {
        // Too close to call — show the disambiguation list.
        if (_stage != DropStage.disambiguate) {
          DropDebugLog.i.add('SHEET',
              '${confirmedList.length} devices within ${_kAutoSelectRssiGap}dBm — showing disambiguation list');
          setState(() {
            _candidates = confirmedList;
            _stage = DropStage.disambiguate;
          });
        } else {
          // Already showing the list — just update the candidates silently
          // so signal-strength bars stay live.
          setState(() => _candidates = confirmedList);
        }
      }
      return;
    }

    // No confirmed receivers yet — handle preview state.
    final previewCandidate = receivers.first;
    if (_stage == DropStage.scanning) {
      setState(() => _stage = DropStage.preview);
      // Start a timeout — if GATT doesn't confirm within 8s, reset to scanning.
      // This handles the simultaneous-drop race condition where both devices
      // try to GATT-connect each other and one fails silently.
      _previewTimeoutTimer?.cancel();
      _previewTimeoutTimer = Timer(_kPreviewTimeout, () {
        if (!mounted) return;
        if (_stage == DropStage.preview) {
          DropDebugLog.i.add('SHEET',
              'Preview timed out (${_kPreviewTimeout.inSeconds}s) — GATT may have failed. Resetting to scan.',
              level: DropLogLevel.warn);
          setState(() {
            _confirmedReceiver = null;
            _stage = DropStage.scanning;
          });
          _bleScannerService.stopScan();
          _bleScannerService.startScan();
        }
      });
    }
    if (_stage == DropStage.preview) {
      setState(() => _confirmedReceiver = previewCandidate);
    }
  }

  void _onReceiverConfirmed(DiscoveredReceiver receiver) {
    _previewTimeoutTimer?.cancel();
    _previewTimeoutTimer = null;
    final nonce = receiver.gattPayload?.nonce;
    // If this nonce was already rejected/consumed, skip and keep scanning.
    if (nonce != null && _exhaustedNonces.contains(nonce)) {
      DropDebugLog.i.add('SHEET',
          'Skipping stale/consumed nonce ${nonce.substring(0, 8)}… — waiting for fresh beacon',
          level: DropLogLevel.warn);
      return;
    }
    final tag = receiver.gattPayload?.zendtag ?? receiver.preview?.zendtag ?? '?';
    DropDebugLog.i.add('SHEET', 'Receiver confirmed: @$tag — routing to tier stage', level: DropLogLevel.ok);
    setState(() => _confirmedReceiver = receiver);

    // Pause discoverable advertising while acting as sender. Every exit from
    // this point onward — success, failure, cancel, back, or sheet dismissal —
    // must go through _resumeDiscoverability(), otherwise the user's
    // "Be Discoverable" toggle keeps reading ON in Profile while nothing is
    // actually broadcasting and nobody can Drop to them.
    _discoverabilityPaused = true;
    unawaited(_discoverabilityService.pause());

    if (widget.amount <= 50) {
      _goTo(DropStage.countdown);
    } else if (widget.amount <= 500) {
      _goTo(DropStage.confirm);
    } else {
      _goTo(DropStage.biometric);
    }
  }

  // ── Signing gate ──────────────────────────────────────────────────────────
  //
  // Called by the tier-confirmation stages (countdown/confirm/biometric) once
  // the user has cleared that UX gate. The tier stages are NOT an
  // authentication gate — they never produce a signing credential. This
  // method is the single place that decides whether the cached session
  // keypair may be used or whether a PIN must be collected first, mirroring
  // SendFlowSheet's _proceedFromRecipient/_submitPin split.

  Future<void> _startSigning() async {
    final policy = SigningPolicyService();
    final cache = WalletSessionCache.instance;
    final needsPin = await policy.requiresPinForAmount(widget.amount);

    if (!mounted) return;

    if (!needsPin && cache.hasKeypair) {
      // Session signing — skip PIN, go straight to processing.
      await _performTransfer(keypairBytes: cache.keypair);
    } else {
      // Either the cache is empty or policy requires PIN regardless —
      // both cases need real PIN entry. There is no other way to obtain
      // a signing credential.
      setState(() {
        _pinDigits = '';
        _pinError = null;
      });
      _goTo(DropStage.pin);
    }
  }

  void _onPinKey(String value) {
    HapticFeedback.lightImpact();

    setState(() {
      _pinError = null;

      if (value == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }

      if (_pinDigits.length >= 6) return;
      _pinDigits += value;
    });

    if (_pinDigits.length == 6) {
      _submitPin();
    }
  }

  Future<void> _submitPin() async {
    final pin = _pinDigits;
    final cache = WalletSessionCache.instance;

    try {
      if (cache.hasKeypair) {
        // Cache is populated but policy required PIN anyway — verify the
        // entered PIN against the cached keypair without a server round-trip,
        // then still sign with the cache (avoids a second decrypt).
        final model = ZendScope.of(context);
        final valid = await model.signingPolicyService
            .verifyPinAgainstCache(pin, model.walletService);
        if (!valid) {
          _onPinRejected(lockOnMaxAttempts: true);
          return;
        }
        await _performTransfer(keypairBytes: cache.keypair);
      } else {
        // No cache — sign directly with the PIN. WalletService decrypts and
        // zeroes the keypair internally; DropService/WalletService throw
        // PinDecryptionException on a wrong PIN.
        await _performTransfer(pin: pin);
      }
    } on PinDecryptionException {
      _onPinRejected(lockOnMaxAttempts: false);
    }
  }

  void _onPinRejected({required bool lockOnMaxAttempts}) {
    if (!mounted) return;
    _pinAttempts++;
    if (_pinAttempts >= 5) {
      if (lockOnMaxAttempts) {
        ZendScope.read(context).appLockService.lock();
      }
      setState(() => _errorMessage = 'Too many incorrect PIN attempts. Please unlock again.');
      _goTo(DropStage.error);
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
      });
      // _performTransfer already advanced the stage to `processing` before
      // the signing attempt failed — return to the PIN stage so the user
      // can retry rather than being stuck on a spinner.
      _goTo(DropStage.pin);
    }
  }

  // ── Transfer execution ────────────────────────────────────────────────────

  /// Performs the actual signing + Drop execution. Exactly one of [pin] or
  /// [keypairBytes] must be provided — enforced by [DropService] itself.
  /// Never called directly by a tier-confirmation stage; always reached via
  /// [_startSigning]/[_submitPin] so a signing credential is guaranteed.
  Future<void> _performTransfer({String? pin, Uint8List? keypairBytes}) async {
    DropDebugLog.i.add('XFER', 'Executing transfer: \$${widget.amount.toStringAsFixed(2)} → @${_confirmedReceiver?.gattPayload?.zendtag ?? '?'}');
    _goTo(DropStage.processing);
    // BleAdvertiserService is no longer used from the sheet.
    // Discoverability is paused via _discoverabilityService in _onReceiverConfirmed.
    try {
      final model = ZendScope.read(context);

      await _dropService.executeDropTransfer(
        beacon: _confirmedReceiver!.gattPayload!,
        amountUsdc: widget.amount,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        pin: pin,
        keypairBytes: keypairBytes,
      );

      if (!mounted) return;
      unawaited(model.fetchBalance());
      unawaited(model.fetchHistory());
      // Mark the nonce exhausted so re-scans don't re-submit it.
      final usedNonce = _confirmedReceiver?.gattPayload?.nonce;
      if (usedNonce != null) _exhaustedNonces.add(usedNonce);
      // Resume discoverability after successful send
      _resumeDiscoverability();

      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
      DropDebugLog.i.add('XFER', 'Transfer success!', level: DropLogLevel.ok);
      _goTo(DropStage.success);
    } on PinDecryptionException {
      rethrow;
    } on ApiException catch (e) {
      DropDebugLog.i.add('XFER', 'API error: ${e.userMessage}', level: DropLogLevel.error);
      if (!mounted) return;

      // Nonce-specific errors: the beacon is stale or already used.
      // Mark it exhausted and silently return to scanning — no error state,
      // just wait for the receiver's BLE service to broadcast a fresh nonce.
      if (e.errorCode == 'NONCE_ALREADY_USED' ||
          e.errorCode == 'NONCE_SUPERSEDED' ||
          e.errorCode == 'INVALID_NONCE') {
        final staleNonce = _confirmedReceiver?.gattPayload?.nonce;
        if (staleNonce != null) _exhaustedNonces.add(staleNonce);
        DropDebugLog.i.add('XFER',
            'Nonce ${staleNonce?.substring(0, 8) ?? '?'}… is ${e.errorCode} — returning to scan for fresh beacon',
            level: DropLogLevel.warn);
        // Resume discoverability so the receiver can still be found (also
        // restarts the scan and clears the stale candidate).
        _returnToScanning();
        return;
      }

      // Resume discoverability on failure so the sender can still be found
      // by someone else — a payment error shouldn't strand them un-Drop-able.
      _resumeDiscoverability();
      setState(() => _errorMessage = e.userMessage);
      _goTo(DropStage.error);
    } catch (e) {
      DropDebugLog.i.add('XFER', 'Unexpected error: $e', level: DropLogLevel.error);
      if (!mounted) return;
      _resumeDiscoverability();
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
      _goTo(DropStage.error);
    }
  }

  // ── Discoverability restore ───────────────────────────────────────────────

  /// Resumes the "Be Discoverable" beacon if this sheet paused it.
  ///
  /// Idempotent and safe to call on every exit path: the service itself
  /// re-reads the persisted preference and no-ops when the user never had
  /// discoverability enabled. The [_discoverabilityPaused] flag stops us
  /// issuing a redundant beacon fetch when nothing was ever paused.
  void _resumeDiscoverability() {
    if (!_discoverabilityPaused) return;
    _discoverabilityPaused = false;
    unawaited(_discoverabilityService.resume());
    DropDebugLog.i.add('SHEET', 'Discoverability resumed');
  }

  // ── Error retry ───────────────────────────────────────────────────────────

  void _retryFromError() {
    setState(() {
      _errorMessage = null;
      _confirmedReceiver = null;
    });
    _restartScan();
    _goTo(DropStage.scanning);
  }

  /// Returns to the scanning stage after the user backs out of a confirmation
  /// or PIN stage. Restores discoverability, since [_onReceiverConfirmed]
  /// paused it on the way in.
  void _returnToScanning({bool clearPin = false}) {
    _resumeDiscoverability();
    setState(() {
      _confirmedReceiver = null;
      _candidates = [];
      if (clearPin) {
        _pinDigits = '';
        _pinError = null;
      }
    });
    _restartScan();
    _goTo(DropStage.scanning);
  }

  void _restartScan() {
    _bleScannerService.stopScan();
    _bleScannerService.startScan();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goTo(DropStage stage) {
    setState(() => _stage = stage);
  }

  void _dismiss() {
    _resumeDiscoverability();
    Navigator.of(context).pop();
  }

  // ── Height fractions ───────────────────────────────────────────────────────

  double get _sheetHeightFraction {
    // All Drop stages run full-screen — the physics/social UX requires space
    // and partial sheets feel like the app is hiding something.
    return 1.0;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != DropStage.processing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _bleScannerService.stopScan();
          _noteController.clear();
        }
      },
      child: AnimatedContainer(
        duration: _sheetResize,
        curve: Curves.easeOutCubic,
        height: screenHeight * _sheetHeightFraction,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.xxl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            // Header row: drag handle (+ debug toggle in debug builds only).
            //
            // The debug toggle is deliberately gated behind kDebugMode. It
            // exposes BLE device identifiers, beacon nonces, zendtags and
            // native crash logs, and previously shipped to production as a
            // near-invisible 20%-alpha glyph sitting next to the drag handle
            // — easy to hit by accident and impossible to interpret.
            if (kDebugMode)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Expanded(child: SizedBox()),
                  const ZendSheetHandle(),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => setState(() => _showDebugPanel = !_showDebugPanel),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16, top: 4),
                          child: Text(
                            '🐛',
                            style: TextStyle(
                              fontSize: 14,
                              color: _showDebugPanel
                                  ? const Color(0xFF52B788)
                                  : const Color(0x33F0F0F0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              const ZendSheetHandle(),
            const SizedBox(height: 8),
            // Note field — shown above stage content on scanning/preview stages
            if (_stage == DropStage.scanning ||
                _stage == DropStage.preview ||
                _stage == DropStage.confirmed ||
                _stage == DropStage.disambiguate)
              _NoteField(
                controller: _noteController,
                expanded: _noteExpanded,
                onToggle: () => setState(() => _noteExpanded = !_noteExpanded),
              ),
            Expanded(
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: _stageTransition,
                    reverseDuration: const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: RepaintBoundary(child: _buildStageContent()),
                  ),
                  if (kDebugMode && _showDebugPanel) const DropDebugPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case DropStage.scanning:
        return DropScannerStage(
          key: const ValueKey('scanning'),
          amount: widget.amount,
        );

      case DropStage.preview:
        if (_confirmedReceiver != null) {
          return DropPreviewStage(
            key: const ValueKey('preview'),
            amount: widget.amount,
            receiver: _confirmedReceiver!,
            isConfirmed: false,
          );
        }
        // Fallback: no receiver yet — keep showing scanner
        return DropScannerStage(
          key: const ValueKey('scanning-fallback'),
          amount: widget.amount,
        );

      case DropStage.confirmed:
        if (_confirmedReceiver != null) {
          return DropPreviewStage(
            key: const ValueKey('confirmed'),
            amount: widget.amount,
            receiver: _confirmedReceiver!,
            isConfirmed: true,
          );
        }
        return DropScannerStage(
          key: const ValueKey('scanning-fallback2'),
          amount: widget.amount,
        );

      case DropStage.disambiguate:
        return DropDisambiguateStage(
          key: const ValueKey('disambiguate'),
          amount: widget.amount,
          candidates: _candidates,
          onSelect: (receiver) {
            setState(() => _candidates = []);
            _onReceiverConfirmed(receiver);
          },
          // No discoverability pause has happened yet at this stage (that
          // only occurs once a single receiver is confirmed), so a plain
          // "back to scanning" is correct here — but routing through the
          // shared helper keeps this stage safe if that ever changes, and
          // is a no-op today since _discoverabilityPaused is still false.
          onCancel: () => _returnToScanning(),
        );

      case DropStage.countdown:
        return DropCountdownStage(
          key: const ValueKey('countdown'),
          amount: widget.amount,
          receiver: _confirmedReceiver!,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          onExecute: _startSigning,
          onCancel: () => _returnToScanning(),
        );

      case DropStage.confirm:
        return DropConfirmStage(
          key: const ValueKey('confirm'),
          amount: widget.amount,
          receiver: _confirmedReceiver!,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          requiresBiometric: false,
          onConfirm: _startSigning,
          onCancel: () => _returnToScanning(),
        );

      case DropStage.biometric:
        return DropConfirmStage(
          key: const ValueKey('biometric'),
          amount: widget.amount,
          receiver: _confirmedReceiver!,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          requiresBiometric: true,
          onConfirm: _startSigning,
          onCancel: () => _returnToScanning(),
        );

      case DropStage.pin:
        return SendPinStage(
          key: const ValueKey('drop-pin'),
          amountFormatted: widget.amount == widget.amount.roundToDouble()
              ? '\$${widget.amount.toStringAsFixed(0)}'
              : '\$${widget.amount.toStringAsFixed(2)}',
          recipientZendtag: _confirmedReceiver?.gattPayload?.zendtag ??
              _confirmedReceiver?.preview?.zendtag ??
              '?',
          note: _noteController.text.trim(),
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: _onPinKey,
          onBack: () => _returnToScanning(clearPin: true),
        );

      case DropStage.processing:
        final model = ZendScope.of(context);
        return DropProcessingStage(
          key: const ValueKey('processing'),
          amount: widget.amount,
          receiver: _confirmedReceiver!,
          senderAvatarUrl: model.currentAvatarUrl,
          senderInitial: model.currentZendtag?.isNotEmpty == true
              ? model.currentZendtag![0].toUpperCase()
              : (model.currentDisplayName?.isNotEmpty == true
                  ? model.currentDisplayName![0].toUpperCase()
                  : 'Y'),
        );

      case DropStage.success:
        return DropSuccessStage(
          key: const ValueKey('success'),
          amount: widget.amount,
          receiver: _confirmedReceiver!,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          onDone: _dismiss,
        );

      case DropStage.error:
        return SendErrorStage(
          key: const ValueKey('error'),
          errorMessage: _errorMessage ?? 'Something went wrong.',
          onRetry: _errorMessage?.contains('Bluetooth') == true
              ? () async {
                  // Re-check Bluetooth state — user may have just turned it on
                  setState(() {
                    _errorMessage = null;
                    _stage = DropStage.scanning;
                  });
                  await _checkBluetoothAndStart();
                }
              : _retryFromError,
          onCancel: _dismiss,
        );
    }
  }
}

// ── Note field widget ─────────────────────────────────────────────────────────

/// Collapsible note field shown above the stage content area during scanning,
/// preview, and confirmed stages.
///
/// - Collapsed + empty: shows "Add note ✎" tap target.
/// - Collapsed + non-empty: shows first 30 chars of note with "…" suffix.
/// - Expanded: shows a `TextField` limited to 100 chars with a live X/100 counter.
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: expanded ? _buildExpanded(context, zt) : _buildCollapsed(context, zt),
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context, ZendTheme zt) {
    final hasNote = controller.text.trim().isNotEmpty;
    final preview = hasNote
        ? (controller.text.trim().length > 30
            ? '${controller.text.trim().substring(0, 30)}…'
            : controller.text.trim())
        : null;

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SolarIconsBold.penNewRound, size: 16, color: zt.textSecondary),
            const SizedBox(width: 4),
            Text(
              hasNote ? preview! : 'Add note',
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, ZendTheme zt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 100,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Add a note…',
                  hintStyle: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 14,
                    color: zt.textSecondary,
                  ),
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontSize: 14,
                  color: zt.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Live X/100 counter
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, _) {
                return Text(
                  '${value.text.length}/100',
                  style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: value.text.length >= 90
                        ? zt.destructive
                        : zt.textSecondary),
                );
              },
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(SolarIconsBold.altArrowUp,
                    size: 18, color: zt.textSecondary),
              ),
            ),
          ],
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          color: zt.border,
        ),
      ],
    );
  }
}
