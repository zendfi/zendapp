import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/drop_models.dart';
import '../../services/ble_scanner_service.dart';
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

  DiscoveredReceiver? _confirmedReceiver;
  List<DiscoveredReceiver> _candidates = []; // for disambiguation
  String? _errorMessage;

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

  @override
  void initState() {
    super.initState();
    final model = ZendScope.of(context);
    _dropService = DropService(
      apiClient: model.walletService.apiClient,
      walletService: model.walletService,
    );
    _bleScannerService = BleScannerService(
      apiClient: model.walletService.apiClient,
    );
    DropDebugLog.i.clear(); // Fresh log for each Drop session
    DropDebugLog.i.add('SHEET', 'Drop sheet opened — amount=\$${widget.amount.toStringAsFixed(2)}');
    _checkBluetoothAndStart();
  }

  @override
  void dispose() {
    _previewTimeoutTimer?.cancel();
    _scanSub?.cancel();
    _bleScannerService.stopScan();
    _bleScannerService.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── BLE lifecycle ─────────────────────────────────────────────────────────

  void _startScanning() {
    _bleScannerService.startScan();
    _scanSub = _bleScannerService.discoveredReceivers.listen(_onReceivers);
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
    final tag = receiver.gattPayload?.zendtag ?? receiver.preview?.zendtag ?? '?';
    DropDebugLog.i.add('SHEET', 'Receiver confirmed: @$tag — routing to tier stage', level: DropLogLevel.ok);
    setState(() => _confirmedReceiver = receiver);

    // Pause discoverable advertising while acting as sender.
    // The discoverability service will be resumed after the transfer
    // completes (success or failure) in _executeTransfer.
    final model = ZendScope.of(context);
    unawaited(model.dropDiscoverabilityService.pause());

    if (widget.amount <= 50) {
      _goTo(DropStage.countdown);
    } else if (widget.amount <= 500) {
      _goTo(DropStage.confirm);
    } else {
      _goTo(DropStage.biometric);
    }
  }

  // ── Transfer execution ────────────────────────────────────────────────────

  Future<void> _executeTransfer() async {
    DropDebugLog.i.add('XFER', 'Executing transfer: \$${widget.amount.toStringAsFixed(2)} → @${_confirmedReceiver?.gattPayload?.zendtag ?? '?'}');
    _goTo(DropStage.processing);
    // BleAdvertiserService is no longer used from the sheet.
    // Discoverability is paused via dropDiscoverabilityService in _onReceiverConfirmed.
    try {
      final model = ZendScope.of(context);
      final policy = SigningPolicyService();
      final cache = WalletSessionCache.instance;
      final needsPin = await policy.requiresPinForAmount(widget.amount);

      if (!needsPin && cache.hasKeypair) {
        await _dropService.executeDropTransfer(
          beacon: _confirmedReceiver!.gattPayload!,
          amountUsdc: widget.amount,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          keypairBytes: cache.keypair,
        );
      } else {
        // For Drop, tier-based confirmation (countdown/confirm/biometric) acts
        // as the auth gate. Fall back to session cache if available.
        await _dropService.executeDropTransfer(
          beacon: _confirmedReceiver!.gattPayload!,
          amountUsdc: widget.amount,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          keypairBytes: cache.keypair,
        );
      }

      if (!mounted) return;
      unawaited(model.fetchBalance());
      unawaited(model.fetchHistory());
      // Resume discoverability after successful send
      unawaited(model.dropDiscoverabilityService.resume());

      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
      DropDebugLog.i.add('XFER', 'Transfer success!', level: DropLogLevel.ok);
      _goTo(DropStage.success);
    } on ApiException catch (e) {
      DropDebugLog.i.add('XFER', 'API error: ${e.userMessage}', level: DropLogLevel.error);
      if (!mounted) return;
      // Resume discoverability on failure so receiver can still be found
      unawaited(ZendScope.of(context).dropDiscoverabilityService.resume());
      setState(() => _errorMessage = e.userMessage);
      _goTo(DropStage.error);
    } catch (e) {
      DropDebugLog.i.add('XFER', 'Unexpected error: $e', level: DropLogLevel.error);
      if (!mounted) return;
      unawaited(ZendScope.of(context).dropDiscoverabilityService.resume());
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
      _goTo(DropStage.error);
    }
  }

  // ── Error retry ───────────────────────────────────────────────────────────

  void _retryFromError() {
    setState(() {
      _errorMessage = null;
      _confirmedReceiver = null;
    });
    _bleScannerService.stopScan();
    _bleScannerService.startScan();
    _goTo(DropStage.scanning);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goTo(DropStage stage) {
    setState(() => _stage = stage);
  }

  void _dismiss() {
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
            // Header row: drag handle + debug toggle
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
            ),
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
                  if (_showDebugPanel) const DropDebugPanel(),
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
          onCancel: () {
            setState(() => _candidates = []);
            _bleScannerService.stopScan();
            _bleScannerService.startScan();
            _goTo(DropStage.scanning);
          },
        );

      case DropStage.countdown:
        return DropCountdownStage(
          key: const ValueKey('countdown'),
          amount: widget.amount,
          receiver: _confirmedReceiver!,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          onExecute: _executeTransfer,
          onCancel: () {
            setState(() => _confirmedReceiver = null);
            _bleScannerService.stopScan();
            _bleScannerService.startScan();
            _goTo(DropStage.scanning);
          },
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
          onConfirm: _executeTransfer,
          onCancel: () {
            setState(() => _confirmedReceiver = null);
            _bleScannerService.stopScan();
            _bleScannerService.startScan();
            _goTo(DropStage.scanning);
          },
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
          onConfirm: _executeTransfer,
          onCancel: () {
            setState(() => _confirmedReceiver = null);
            _bleScannerService.stopScan();
            _bleScannerService.startScan();
            _goTo(DropStage.scanning);
          },
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
                fontFamily: 'DMSans',
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
                    fontFamily: 'DMSans',
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
                  fontFamily: 'DMSans',
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
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: value.text.length >= 90
                        ? zt.destructive
                        : zt.textSecondary,
                  ),
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
