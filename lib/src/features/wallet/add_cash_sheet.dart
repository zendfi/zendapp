import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/zend_features.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/add_cash_models.dart';
import '../../design/zend_modal.dart';

/// Add Cash — funding a Zend balance from outside Zend.
///
/// Both rails hand the user *instructions* and then get out of the way:
/// crypto gives an address, naira gives bank transfer details. The app never
/// collects card data and never drives a payment, which is exactly why this
/// lives in-app rather than on a hosted page — there is nothing to host that
/// isn't an address and an account number.
///
/// Deliberately has **no "I've sent it" confirmation step.** Asking the user
/// to tell us about money we can already see would be theatre: the provider
/// webhooks credit the balance and the arrival is announced by a banner
/// (see `FundsArrivedBanner` in zend_shell.dart). The last screen of each
/// rail ends in a plain "Done".
///
/// ── Layout contract ──────────────────────────────────────────────────────
/// Mirrors `zend_entry_sheet.dart`: explicit keyboard-aware height, no
/// `useSafeArea`, no `FractionallySizedBox`, and action buttons pinned
/// *outside* the scroll view. The naira step has an OS keyboard, and that
/// combination is the one that works — see that file's contract for the
/// three things that break otherwise.
/// No zendtag-placeholder guard here, unlike Receive.
///
/// Funding used to go through the public `WHERE zendtag = $1 AND is_active`
/// routes, so an account still on an email-placeholder handle genuinely could
/// not be funded and had to claim a handle first. Both rails now resolve the
/// recipient from the JWT (`/api/zend/crypto/deposit-address` and
/// `/api/zend/payin/ngn/prepare`), so there is nothing left to guard against —
/// and requiring a handle purely to put money *in* was friction at the worst
/// possible moment in the funnel.
///
/// Receive keeps its guard for an unrelated reason: a `zdfi.me/@handle` link
/// would expose the email placeholder to whoever it is shared with.
Future<void> showAddCashSheet(BuildContext context) async {
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AddCashSheet(),
  );
}

enum _Stage { method, cryptoChain, cryptoAddress, ngnAmount, ngnInstructions }

class AddCashSheet extends StatefulWidget {
  const AddCashSheet({super.key});

  @override
  State<AddCashSheet> createState() => _AddCashSheetState();
}

class _AddCashSheetState extends State<AddCashSheet> {
  _Stage _stage = _Stage.method;

  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();

  List<DepositChain> _chains = const [];
  bool _loadingChains = false;
  String? _chainsError;

  DepositChain? _selectedChain;
  DepositAddress? _address;
  bool _loadingAddress = false;
  String? _addressError;

  NgnPayinInstructions? _instructions;
  bool _preparing = false;
  String? _ngnError;

  /// Naira pay-in is bounded by the provider — mirrored here so the user
  /// finds out before we provision an order rather than after.
  static const _minUsd = 0.5;
  static const _maxUsd = 10000.0;

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  double get _amountUsd => double.tryParse(_amountController.text.trim()) ?? 0;

  void _goTo(_Stage stage) {
    setState(() => _stage = stage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (stage == _Stage.ngnAmount) {
        _amountFocus.requestFocus();
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  // ── Crypto ──────────────────────────────────────────────────────────────

  Future<void> _startCrypto() async {
    _goTo(_Stage.cryptoChain);
    if (_chains.isNotEmpty || _loadingChains) return;
    setState(() {
      _loadingChains = true;
      _chainsError = null;
    });
    try {
      final chains = await ZendScope.read(
        context,
      ).walletService.apiClient.getDepositChains();
      if (!mounted) return;
      setState(() {
        _chains = chains;
        _loadingChains = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingChains = false;
        _chainsError = "Couldn't load networks. Try again.";
      });
    }
  }

  Future<void> _pickChain(DepositChain chain) async {
    setState(() {
      _selectedChain = chain;
      _address = null;
      _addressError = null;
      _loadingAddress = true;
    });
    _goTo(_Stage.cryptoAddress);

    final model = ZendScope.read(context);
    try {
      final addr = await model.walletService.apiClient.getDepositAddress(
        chainId: chain.chainId,
      );
      if (!mounted) return;
      setState(() {
        _address = addr;
        _loadingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAddress = false;
        _addressError =
            "Couldn't get a deposit address for ${chain.displayName}.";
      });
    }
  }

  // ── Naira ───────────────────────────────────────────────────────────────

  Future<void> _prepareNgn() async {
    final amount = _amountUsd;
    if (amount < _minUsd || amount > _maxUsd || _preparing) return;

    setState(() {
      _preparing = true;
      _ngnError = null;
    });
    final model = ZendScope.read(context);
    try {
      final instructions = await model.walletService.apiClient.prepareNgnPayin(
        amountUsd: amount,
      );
      if (!mounted) return;
      setState(() {
        _instructions = instructions;
        _preparing = false;
      });
      _goTo(_Stage.ngnInstructions);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _ngnError = "Couldn't get transfer details. Try again.";
      });
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied',
          style: const TextStyle(fontFamily: 'Geist'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String get _title => switch (_stage) {
    _Stage.method => 'Add cash',
    _Stage.cryptoChain => 'Choose a network',
    _Stage.cryptoAddress => _selectedChain?.displayName ?? 'Deposit',
    _Stage.ngnAmount => 'How much?',
    _Stage.ngnInstructions => 'Make the transfer',
  };

  void _back() {
    switch (_stage) {
      case _Stage.method:
        Navigator.of(context).pop();
      case _Stage.cryptoChain:
        _goTo(_Stage.method);
      case _Stage.cryptoAddress:
        _goTo(_Stage.cryptoChain);
      case _Stage.ngnAmount:
        _goTo(_Stage.method);
      case _Stage.ngnInstructions:
        // Going back would re-provision a second order for the same money.
        // Closing is the honest action once instructions exist.
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;

    final sheetHeight = ((mq.size.height - keyboardInset) * 0.92).clamp(
      320.0,
      mq.size.height,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.xxl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              const ZendSheetHandle(),
              const SizedBox(height: 4),
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _back,
                      icon: Icon(
                        _stage == _Stage.method ||
                                _stage == _Stage.ngnInstructions
                            ? PhosphorIconsRegular.x
                            : PhosphorIconsRegular.caretLeft,
                        color: zt.textPrimary,
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: zt.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: ZendMotion.sheetEnter,
                  child: switch (_stage) {
                    _Stage.method => _buildMethod(zt),
                    _Stage.cryptoChain => _buildChainPicker(zt),
                    _Stage.cryptoAddress => _buildAddress(zt),
                    _Stage.ngnAmount => _buildAmount(zt),
                    _Stage.ngnInstructions => _buildInstructions(zt),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: how ─────────────────────────────────────────────────────────

  Widget _buildMethod(ZendTheme zt) {
    return ListView(
      key: const ValueKey('method'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Money added this way lands in your Zend balance, ready to send.',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14,
            height: 1.4,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        _MethodRow(
          icon: PhosphorIconsRegular.currencyBtc,
          title: 'Crypto',
          subtitle: 'Send stablecoins or crypto from any wallet or exchange',
          onTap: _startCrypto,
        ),
        const SizedBox(height: 10),
        _MethodRow(
          icon: PhosphorIconsRegular.bank,
          title: 'Bank transfer',
          subtitle: 'Transfer naira from your bank app',
          onTap: () => _goTo(_Stage.ngnAmount),
        ),
        // Other fiat currencies run on Bridge, which is built out for the
        // platform but has no per-user funding route yet — virtual accounts
        // are provisioned against a Bridge customer, not a Zend handle. Shown
        // only when that exists; see [ZendFeatures.addCashOtherCurrencies].
        if (ZendFeatures.addCashOtherCurrencies) ...[
          const SizedBox(height: 10),
          _MethodRow(
            icon: PhosphorIconsRegular.globeHemisphereWest,
            title: 'Other currencies',
            subtitle: 'USD, EUR, GBP and more',
            onTap: () {},
          ),
        ],
      ],
    );
  }

  // ── Step 2a: which network ──────────────────────────────────────────────

  Widget _buildChainPicker(ZendTheme zt) {
    if (_loadingChains) {
      return const Center(
        key: ValueKey('chainsLoading'),
        child: ZendLoader(size: 24),
      );
    }
    if (_chainsError != null) {
      return _ErrorState(
        key: const ValueKey('chainsError'),
        message: _chainsError!,
        onRetry: _startCrypto,
      );
    }
    return ListView.separated(
      key: const ValueKey('chains'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _chains.length,
      separatorBuilder: (_, _) => Divider(color: zt.border, height: 1),
      itemBuilder: (context, i) {
        final chain = _chains[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _pickChain(chain),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chain.displayName,
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: zt.textPrimary,
                          ),
                        ),
                        if (chain.blockchainName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${chain.symbol} on ${chain.blockchainName}',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 12,
                              color: zt.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.caretRight,
                    size: 16,
                    color: zt.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Step 3a: the address ────────────────────────────────────────────────

  Widget _buildAddress(ZendTheme zt) {
    if (_loadingAddress) {
      return const Center(
        key: ValueKey('addrLoading'),
        child: ZendLoader(size: 24),
      );
    }
    if (_addressError != null || _address == null) {
      return _ErrorState(
        key: const ValueKey('addrError'),
        message: _addressError ?? 'Something went wrong.',
        onRetry: _selectedChain != null
            ? () => _pickChain(_selectedChain!)
            : null,
      );
    }

    final addr = _address!;
    return Column(
      key: const ValueKey('addr'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(ZendRadii.lg),
                  ),
                  child: QrImageView(
                    data: addr.depositAddress,
                    version: QrVersions.auto,
                    size: 180,
                    backgroundColor: Colors.white,
                    // Low error correction keeps the pattern coarse, which
                    // scans more reliably on a phone screen than a dense one.
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                  ),
                ),
                const SizedBox(height: 18),
                // The address itself, selectable and tappable to copy — the
                // one thing the user actually needs off this screen.
                GestureDetector(
                  onTap: () => _copy(addr.depositAddress, 'Address'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.lg),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            addr.depositAddress,
                            style: ZendTextStyles.tabularNumeric.copyWith(
                              fontSize: 13,
                              height: 1.4,
                              color: zt.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          PhosphorIconsRegular.copy,
                          size: 18,
                          color: zt.accent,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Sending the wrong asset or the wrong network is the one way
                // to actually lose money here, so it's stated plainly rather
                // than buried in fine print.
                _Notice(
                  zt: zt,
                  icon: PhosphorIconsRegular.warning,
                  text:
                      'Only send ${addr.symbol.isNotEmpty ? addr.symbol : 'funds'} '
                      'on ${addr.blockchainName.isNotEmpty ? addr.blockchainName : addr.displayName}. '
                      'Anything else sent to this address is lost.',
                ),
                if (!addr.isStatic) ...[
                  const SizedBox(height: 10),
                  _Notice(
                    zt: zt,
                    icon: PhosphorIconsRegular.clock,
                    text:
                        'This address is for this deposit only — '
                        'come back here for a fresh one next time.',
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  "We'll let you know the moment it lands.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  // ── Step 2b: amount ─────────────────────────────────────────────────────

  Widget _buildAmount(ZendTheme zt) {
    final amount = _amountUsd;
    final tooSmall = amount > 0 && amount < _minUsd;
    final tooBig = amount > _maxUsd;
    final canContinue = amount >= _minUsd && amount <= _maxUsd && !_preparing;

    return Column(
      key: const ValueKey('amount'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              children: [
                Text(
                  'Amount to add',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountController,
                  focusNode: _amountFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: zt.textPrimary,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$',
                    prefixStyle: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: zt.textSecondary,
                    ),
                    // Explicitly borderless — the global InputDecorationTheme
                    // fills and pill-rounds inputs, which would draw a capsule
                    // around the big figure.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                  onChanged: (_) => setState(() => _ngnError = null),
                ),
                const SizedBox(height: 8),
                if (tooSmall)
                  _InlineError('Minimum is \$${_minUsd.toStringAsFixed(2)}')
                else if (tooBig)
                  _InlineError('Maximum is \$${_maxUsd.toStringAsFixed(0)}')
                else if (_ngnError != null)
                  _InlineError(_ngnError!)
                else
                  Text(
                    "You'll see the exact naira amount next.",
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      color: zt.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: canContinue ? _prepareNgn : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: zt.accent,
                foregroundColor: ZendColors.textOnDeep,
                disabledBackgroundColor: zt.border,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
              child: _preparing
                  ? const ZendLoader(
                      size: 20,
                      strokeWidth: 2,
                      color: ZendColors.textOnDeep,
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 3b: bank instructions ──────────────────────────────────────────

  Widget _buildInstructions(ZendTheme zt) {
    final inst = _instructions!;
    return Column(
      key: const ValueKey('instructions'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Transfer exactly',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: zt.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₦${_formatMoney(inst.fiatAmount)}',
                        style: ZendTextStyles.tabularNumeric.copyWith(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: zt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You get \$${inst.usdcAmount.toStringAsFixed(2)} '
                        '· ₦${_formatMoney(inst.exchangeRate)}/\$',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: zt.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _DetailRow(zt: zt, label: 'Bank', value: inst.bankName),
                Divider(color: zt.border, height: 1),
                _DetailRow(
                  zt: zt,
                  label: 'Account number',
                  value: inst.accountNumber,
                  monospace: true,
                  onCopy: () => _copy(inst.accountNumber, 'Account number'),
                ),
                Divider(color: zt.border, height: 1),
                _DetailRow(
                  zt: zt,
                  label: 'Account name',
                  value: inst.accountName,
                ),
                const SizedBox(height: 16),
                _Notice(
                  zt: zt,
                  icon: PhosphorIconsRegular.warning,
                  text:
                      'Send the exact amount from your own bank account. '
                      'A different amount can delay or fail the transfer.',
                ),
                const SizedBox(height: 10),
                Text(
                  "We'll let you know the moment it lands.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  static String _formatMoney(double v) {
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: zt.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: zt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12,
                        height: 1.3,
                        color: zt.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 16,
                color: zt.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.zt,
    required this.label,
    required this.value,
    this.monospace = false,
    this.onCopy,
  });

  final ZendTheme zt;
  final String label;
  final String value;
  final bool monospace;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final valueStyle = monospace
        ? ZendTextStyles.tabularNumeric.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: zt.textPrimary,
          )
        : TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: zt.textPrimary,
          );

    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 2,
                style: valueStyle,
              ),
            ),
            if (onCopy != null) ...[
              const SizedBox(width: 8),
              Icon(PhosphorIconsRegular.copy, size: 16, color: zt.accent),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.zt, required this.icon, required this.text});

  final ZendTheme zt;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: zt.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                height: 1.35,
                color: zt.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        color: ZendColors.destructive,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlineActionButton(label: 'Try again', onPressed: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}
