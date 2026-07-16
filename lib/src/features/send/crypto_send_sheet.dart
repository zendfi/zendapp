import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/crypto_send_models.dart';
import '../../services/signing_policy_service.dart';
import '../../services/sound_service.dart';
import '../../services/wallet_session_cache.dart';
import 'package:solar_icons/solar_icons.dart';

Future<void> showCryptoSendSheet(BuildContext context,
    {required double amount}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => CryptoSendSheet(amount: amount),
  );
}

enum CryptoSendStage {
  chainAndAddress,
  quote,
  pin,
  processing,
  success,
  error,
}

class CryptoSendSheet extends StatefulWidget {
  const CryptoSendSheet({super.key, required this.amount});

  final double amount;

  @override
  State<CryptoSendSheet> createState() => _CryptoSendSheetState();
}

class _CryptoSendSheetState extends State<CryptoSendSheet>
    with SingleTickerProviderStateMixin {
  static const Duration _stageTransition = Duration(milliseconds: 180);
  static const Duration _sheetResize = Duration(milliseconds: 220);

  CryptoSendStage _stage = CryptoSendStage.chainAndAddress;

  List<Map<String, dynamic>> _chains = [];
  bool _loadingChains = false;
  Map<String, dynamic>? _selectedChain;

  final _addressController = TextEditingController();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _filteredChains = [];

  CryptoSendQuote? _quote;

  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

  String? _errorMessage;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChains());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChains() async {
    if (!mounted) return;
    setState(() => _loadingChains = true);
    try {
      final model = ZendScope.of(context);
      final chains = await model.walletService.apiClient.getSupportedChains();
      if (!mounted) return;
      setState(() {
        _chains = chains;
        _filteredChains = chains;
        _loadingChains = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingChains = false);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _filteredChains = _chains;
      } else {
        final q = query.trim().toLowerCase();
        _filteredChains = _chains.where((c) {
          final name = (c['display_name'] as String? ?? '').toLowerCase();
          final symbol = (c['symbol'] as String? ?? '').toLowerCase();
          return name.contains(q) || symbol.contains(q);
        }).toList();
      }
    });
  }

  double get _sheetHeightFraction {
    switch (_stage) {
      case CryptoSendStage.chainAndAddress:
        return 0.92;
      case CryptoSendStage.quote:
        return 0.65;
      case CryptoSendStage.pin:
        return 0.70;
      case CryptoSendStage.processing:
        return 0.45;
      case CryptoSendStage.success:
        return 0.50;
      case CryptoSendStage.error:
        return 0.55;
    }
  }

  String get _amountFormatted {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _amountFormattedExact =>
      '\$${widget.amount.toStringAsFixed(2)}';

  String _truncateAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
  }

  Future<void> _getQuote() async {
    setState(() => _stage = CryptoSendStage.processing);
    try {
      final model = ZendScope.of(context);
      final quote = await model.walletService.apiClient.getCryptoSendQuote(
        chainId: _selectedChain!['chain_id'] as int,
        destinationAddress: _addressController.text.trim(),
        amountUsdc: widget.amount,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _stage = CryptoSendStage.quote;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not get quote. Please try again.';
        _stage = CryptoSendStage.error;
      });
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
      _executePin();
    }
  }

  Future<void> _proceedFromQuote() async {
    final policy = SigningPolicyService();
    final cache = WalletSessionCache.instance;
    final needsPin = await policy.requiresPinForAmount(widget.amount);

    if (!needsPin && cache.hasKeypair) {
      // Session signing — skip PIN and execute directly with cached keypair
      setState(() => _stage = CryptoSendStage.processing);
      await _runCryptoSend(pin: null, keypairBytes: cache.keypair);
    } else {
      setState(() => _stage = CryptoSendStage.pin);
    }
  }

  Future<void> _executePin() async {
    final pin = _pinDigits;
    setState(() => _stage = CryptoSendStage.processing);
    try {
      final model = ZendScope.of(context);
      final cache = WalletSessionCache.instance;
      if (cache.hasKeypair) {
        final valid = await model.signingPolicyService.verifyPinAgainstCache(pin, model.walletService);
        if (!valid) {
          if (!mounted) return;
          _pinAttempts++;
          if (_pinAttempts >= 5) {
            model.appLockService.lock();
            setState(() {
              _errorMessage = 'Too many incorrect PIN attempts. Please unlock again.';
              _stage = CryptoSendStage.error;
            });
          } else {
            _shakeController.forward(from: 0);
            setState(() {
              _pinDigits = '';
              _pinError = 'Incorrect PIN';
              _stage = CryptoSendStage.pin;
            });
          }
          return;
        }
        // PIN verified — sign with session cache
        await _runCryptoSend(pin: null, keypairBytes: cache.keypair);
      } else {
        // No session cache — sign directly with PIN
        await _runCryptoSend(pin: pin, keypairBytes: null);
      }
    } on PinDecryptionException {
      if (!mounted) return;
      _pinAttempts++;
      if (_pinAttempts >= 5) {
        setState(() {
          _errorMessage = 'Too many incorrect PIN attempts.';
          _stage = CryptoSendStage.error;
        });
      } else {
        _shakeController.forward(from: 0);
        setState(() {
          _pinDigits = '';
          _pinError = 'Incorrect PIN';
          _stage = CryptoSendStage.pin;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = CryptoSendStage.error;
      });
    }
  }

  Future<void> _runCryptoSend({String? pin, dynamic keypairBytes}) async {
    try {
      final model = ZendScope.of(context);
      final quote = _quote!;

      // Build and sign the USDC transfer from the user's wallet to the
      // Dextopus deposit address. This matches the pattern used by bank-send
      // and zend-to-zend transfers: user signs, server co-signs as fee-payer.
      final String signedTx;
      if (keypairBytes != null) {
        signedTx = await model.walletService.buildAndSignTransactionToAddressFromCache(
          keypairBytes: keypairBytes,
          amountUsdc: widget.amount,
          destinationAddress: quote.dextopusDepositAddress,
          blockhash: quote.blockhash,
          feePayerAddress: quote.feePayer,
        );
      } else {
        signedTx = await model.walletService.buildAndSignTransactionToAddress(
          pin: pin!,
          amountUsdc: widget.amount,
          destinationAddress: quote.dextopusDepositAddress,
          blockhash: quote.blockhash,
          feePayerAddress: quote.feePayer,
        );
      }

      await model.walletService.apiClient.executeCryptoSend(
        quoteId: quote.quoteId,
        partiallySignedTx: signedTx,
      );

      if (!mounted) return;
      setState(() => _stage = CryptoSendStage.success);
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
      unawaited(model.fetchBalance());
      unawaited(model.fetchHistory());
    } on PinDecryptionException {
      rethrow;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = CryptoSendStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Transfer failed. Please try again.';
        _stage = CryptoSendStage.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != CryptoSendStage.processing,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
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
              const ZendSheetHandle(),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case CryptoSendStage.chainAndAddress:
        return _buildChainAndAddressStage();
      case CryptoSendStage.quote:
        return _buildQuoteStage();
      case CryptoSendStage.pin:
        return _buildPinStage();
      case CryptoSendStage.processing:
        return _buildProcessingStage();
      case CryptoSendStage.success:
        return _buildSuccessStage();
      case CryptoSendStage.error:
        return _buildErrorStage();
    }
  }

  // ── Stage: Chain & Address ──────────────────────────────────────────────────

  Widget _buildChainAndAddressStage() {
    final zt = ZendTheme.of(context);
    final canGetQuote = _selectedChain != null &&
        _addressController.text.trim().isNotEmpty;

    return KeyedSubtree(
      key: const ValueKey('chainAndAddress'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Send $_amountFormatted to',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            // Search field
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search chains...',
                prefixIcon: Icon(SolarIconsBold.magnifier,
                    size: 20, color: zt.textSecondary),
                filled: true,
                fillColor: zt.bgSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            // Chain list
            if (_loadingChains)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: ZendLoader(size: 24)),
              )
            else if (_filteredChains.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No chains found'
                      : 'No chains available',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredChains.length,
                  itemBuilder: (context, i) {
                    final chain = _filteredChains[i];
                    final displayName =
                        chain['display_name'] as String? ?? '';
                    final symbol = chain['symbol'] as String? ?? '';
                    final isSelected = _selectedChain != null &&
                        _selectedChain!['chain_id'] == chain['chain_id'];
                    final avatarLabel =
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ZendRadii.md),
                        onTap: () => setState(() => _selectedChain = chain),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? zt.accent.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(ZendRadii.md),
                            border: isSelected
                                ? Border.all(
                                    color: zt.accent.withValues(alpha: 0.3))
                                : null,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: zt.bgSecondary,
                                child: Text(
                                  avatarLabel,
                                  style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: zt.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: TextStyle(
                                        fontFamily: 'DMSans',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: zt.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      symbol,
                                      style: TextStyle(
                                        fontFamily: 'DMMono',
                                        fontSize: 12,
                                        color: zt.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(SolarIconsBold.checkCircle,
                                    size: 18, color: zt.accent),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            // Address field
            TextField(
              controller: _addressController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Destination wallet address',
                filled: true,
                fillColor: zt.bgSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZendRadii.lg),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: canGetQuote ? _getQuote : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: zt.accent,
                  foregroundColor: ZendColors.textOnDeep,
                  disabledBackgroundColor: zt.border,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.lg),
                  ),
                ),
                child: const Text(
                  'Get quote',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage: Quote ────────────────────────────────────────────────────────────

  Widget _buildQuoteStage() {
    final zt = ZendTheme.of(context);
    final quote = _quote!;
    final symbol = _selectedChain?['symbol'] as String? ?? '';
    final address = _addressController.text.trim();

    return KeyedSubtree(
      key: const ValueKey('quote'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => setState(() {
                  _quote = null;
                  _stage = CryptoSendStage.chainAndAddress;
                }),
                child: Icon(SolarIconsBold.altArrowLeft,
                    color: zt.textPrimary, size: 22),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sending $_amountFormattedExact',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '→ ~${quote.estimatedReceiveAmount} $symbol on ${quote.destinationChainDisplay}',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
            if (quote.estimatedFeeUsdc > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Bridge fee: ~\$${quote.estimatedFeeUsdc.toStringAsFixed(4)}',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 12,
                  color: zt.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _truncateAddress(address),
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 12,
                color: zt.textSecondary,
              ),
            ),
            const Spacer(),
            PrimaryButton(
              label: 'Confirm',
              onPressed: _proceedFromQuote,
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage: PIN ──────────────────────────────────────────────────────────────

  Widget _buildPinStage() {
    final zt = ZendTheme.of(context);
    final compact = MediaQuery.of(context).size.height < 760;
    final chainName = _selectedChain?['display_name'] as String? ?? '';
    final address = _addressController.text.trim();

    return KeyedSubtree(
      key: const ValueKey('pin'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => setState(() {
                  _pinDigits = '';
                  _pinError = null;
                  _stage = CryptoSendStage.quote;
                }),
                child: Icon(SolarIconsBold.altArrowLeft,
                    color: zt.textPrimary, size: 22),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_amountFormattedExact to $chainName',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _truncateAddress(address),
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
            SizedBox(height: compact ? 20 : 28),
            // PIN dots with shake
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: _CryptoPinDots(filledCount: _pinDigits.length),
            ),
            const SizedBox(height: 10),
            Text(
              _pinError ?? 'Enter your PIN',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: _pinError != null
                    ? ZendColors.destructive
                    : zt.textSecondary,
              ),
            ),
            const Spacer(),
            _CryptoPinKeypad(
              onTap: _onPinKey,
              keyHeight: compact ? 56 : 64,
            ),
            SizedBox(height: compact ? 4 : 12),
          ],
        ),
      ),
    );
  }

  // ── Stage: Processing ───────────────────────────────────────────────────────

  Widget _buildProcessingStage() {
    return KeyedSubtree(
      key: const ValueKey('processing'),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZendLoader(size: 32),
            const SizedBox(height: 20),
            Text(
              'Processing...',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: ZendTheme.of(context).textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage: Success ──────────────────────────────────────────────────────────

  Widget _buildSuccessStage() {
    return KeyedSubtree(
      key: const ValueKey('success'),
      child: _CryptoSuccessStage(
        amountFormattedExact: _amountFormattedExact,
        destinationChainDisplay: _quote?.destinationChainDisplay ?? '',
        onDone: () => Navigator.of(context).pop(),
      ),
    );
  }

  // ── Stage: Error ────────────────────────────────────────────────────────────

  Widget _buildErrorStage() {
    final zt = ZendTheme.of(context);
    return KeyedSubtree(
      key: const ValueKey('error'),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: ZendColors.destructive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(SolarIconsBold.closeCircle, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Oops',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 32,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: zt.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Try again',
                  onPressed: () {
                    setState(() {
                      _pinDigits = '';
                      _pinError = null;
                      _errorMessage = null;
                    });
                    _proceedFromQuote();
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlineActionButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Success Stage Widget ────────────────────────────────────────────────────

class _CryptoSuccessStage extends StatefulWidget {
  const _CryptoSuccessStage({
    required this.amountFormattedExact,
    required this.destinationChainDisplay,
    required this.onDone,
  });

  final String amountFormattedExact;
  final String destinationChainDisplay;
  final VoidCallback onDone;

  @override
  State<_CryptoSuccessStage> createState() => _CryptoSuccessStageState();
}

class _CryptoSuccessStageState extends State<_CryptoSuccessStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: ZendColors.positive,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(SolarIconsBold.checkCircle, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sent!',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 40,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.amountFormattedExact} → ${widget.destinationChainDisplay}',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Done',
                onPressed: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PIN Dots ────────────────────────────────────────────────────────────────

class _CryptoPinDots extends StatelessWidget {
  const _CryptoPinDots({required this.filledCount});

  final int filledCount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final filled = index < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? zt.accent : Colors.transparent,
              border: Border.all(
                color: filled ? zt.accent : zt.border,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ── PIN Keypad ──────────────────────────────────────────────────────────────

class _CryptoPinKeypad extends StatelessWidget {
  const _CryptoPinKeypad({required this.onTap, required this.keyHeight});

  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', 'del',
    ];

    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == 2 ? 0 : 10,
                      bottom: row == 3 ? 0 : 12,
                    ),
                    child: keys[row * 3 + col].isEmpty
                        ? SizedBox(height: keyHeight)
                        : _CryptoPinKeypadKey(
                            label: keys[row * 3 + col],
                            keyHeight: keyHeight,
                            onTap: () => onTap(keys[row * 3 + col]),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _CryptoPinKeypadKey extends StatefulWidget {
  const _CryptoPinKeypadKey({
    required this.label,
    required this.onTap,
    required this.keyHeight,
  });

  final String label;
  final VoidCallback onTap;
  final double keyHeight;

  @override
  State<_CryptoPinKeypadKey> createState() => _CryptoPinKeypadKeyState();
}

class _CryptoPinKeypadKeyState extends State<_CryptoPinKeypadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: ZendMotion.keypadPress,
        curve: Curves.easeOut,
        scale: _pressed ? 0.94 : 1,
        child: SizedBox(
          height: widget.keyHeight,
          child: Center(
            child: widget.label == 'del'
                ? ZendBackspaceIcon(color: zt.textPrimary, size: 24)
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 24,
                      color: zt.textPrimary,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
