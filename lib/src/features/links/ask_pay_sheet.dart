part of 'zlink_sheets.dart';

/// Paying an ask link (a request). Built in the same frame as Add cash and
/// Bank send: a handle, a header with close/back and a title, and steps that
/// fade into each other.
///
/// Two ways to pay:
/// * **From my Zend**: a gasless transfer from the balance.
/// * **Bank transfer**: the payer sends Naira from their bank app to an
///   account the bank provider gives; it goes straight to the link's owner
///   and never passes through the payer's balance. This is where someone new
///   to Zend (or with too little in it) starts.
enum _AskStage {
  loading,
  unavailable,
  method,
  amount,
  confirm,
  country,
  bankAmount,
  preparing,
  bankDetails,
  bankFailed,
  paid,
  bankPaid,
}

class _AskPaySheet extends StatefulWidget {
  const _AskPaySheet({required this.id});
  final String id;
  @override
  State<_AskPaySheet> createState() => _AskPaySheetState();
}

class _AskPaySheetState extends State<_AskPaySheet> {
  _AskStage _stage = _AskStage.loading;

  /// Where the person landed: closing from here closes the sheet.
  _AskStage _first = _AskStage.method;

  Map<String, dynamic>? _preview;
  String? _unavailable;
  String? _error;
  bool _paying = false;

  /// Whether the balance could pay this link.
  bool _balanceCovers = false;
  double _balance = 0;

  /// Set from the pay response when "Message" should show after paying.
  String? _messageUserId;

  final _amount = TextEditingController();
  final _amountFocus = FocusNode();

  /// Naira when a rate is known as the sheet opens, else dollars. Paying by
  /// bank is always in Naira.
  final AmountEntry _entry = AmountEntry.current();

  Map<String, dynamic>? _bank;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _v => _preview!;
  String get _payee => _v['payee_name'] as String? ?? 'them';
  bool get _fixed => _v['amount_usd'] != null;

  Future<void> _load() async {
    final model = ZendScope.of(context);
    final Map<String, dynamic> v;
    try {
      v = await zlinkServiceOf(context).previewAsk(widget.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _unavailable = "This link doesn't exist";
        _stage = _AskStage.unavailable;
      });
      return;
    }
    if (v['status'] != 'active') {
      if (!mounted) return;
      setState(() {
        _preview = v;
        _unavailable = 'This link is no longer collecting';
        _stage = _AskStage.unavailable;
      });
      return;
    }
    // Someone new to Zend has nothing to pay from yet. Right after creating
    // an account the first reads can fail while the session settles, so give
    // it a few tries before deciding.
    for (final wait in const [0, 2, 4]) {
      if (model.balanceLoaded) break;
      if (wait > 0) await Future<void>.delayed(Duration(seconds: wait));
      await model.fetchBalance().timeout(
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    }
    final known = model.balanceLoaded;
    final have = model.spendableBalance;
    final ask = (v['amount_usd'] as num?)?.toDouble();
    final covers = have > 0 && (ask == null || have >= ask);
    if (!mounted) return;
    setState(() {
      _preview = v;
      _balance = have;
      // Unknown balance: still offer it, in case there is money there.
      _balanceCovers = covers || !known;
      // Nothing to pay from: start straight at the bank transfer.
      _first = covers ? _AskStage.method : _AskStage.country;
      _stage = _first;
    });
  }

  void _goTo(_AskStage stage) {
    setState(() {
      _stage = stage;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (stage == _AskStage.amount || stage == _AskStage.bankAmount) {
        _amountFocus.requestFocus();
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  // ── From my Zend ────────────────────────────────────────────────────────

  void _chooseZend() {
    _amount.clear();
    _goTo(_fixed ? _AskStage.confirm : _AskStage.amount);
  }

  double get _zendAmountUsd =>
      _fixed ? (_v['amount_usd'] as num).toDouble() : _entry.usd(_amount.text);

  String get _zendAmountLabel => _fixed
      ? zlinkAmountLabel(_v)
      : _entry.format(_entry.usd(_amount.text));

  Future<void> _pay() async {
    final amount = _zendAmountUsd;
    if (amount <= 0 || _paying) return;
    final model = ZendScope.of(context);
    final service = zlinkServiceOf(context);
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final paid = await service.payAsk(widget.id, amountUsd: amount);
      model.fetchBalance();
      // "Pay with Zend" from a developer's site: send the payer back there.
      final token = paid['return_token'] as String?;
      final redirect = paid['redirect_url'] as String?;
      final devId = paid['dev_request_id'] as String?;
      if (token != null && redirect != null && devId != null) {
        await DevReturnRedirectService.redirectAndReportOutcome(
          apiClient: model.walletService.apiClient,
          requestId: devId,
          redirectUrl: redirect,
          token: token,
          platform: defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        );
      }
      // A developer checkout sends the payer back to the site: no chat.
      final payeeId = paid['payee_user_id'];
      final offerChat =
          paid['dev_request_id'] == null &&
          zlinkCanMessage(
            userId: payeeId,
            fromApp: paid['from_app'],
            name: _v['payee_name'],
          );
      if (!mounted) return;
      _messageUserId = offerChat ? payeeId as String : null;
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
      _goTo(_AskStage.paid);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ZlinkException
              ? e.message
              : "That didn't go through. Try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Closes this sheet and opens the chat. Everything the chat needs is
  /// captured first, because this sheet's context goes away on pop.
  void _message(String userId) {
    final model = ZendScope.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    unawaited(
      _openChatWith(
        model: model,
        navigator: navigator,
        messenger: messenger,
        userId: userId,
      ),
    );
  }

  // ── By bank ─────────────────────────────────────────────────────────────

  void _chooseBank() => _goTo(_AskStage.country);

  void _chooseCountry() {
    if (_fixed) {
      _prepareBank();
    } else {
      _amount.clear();
      _goTo(_AskStage.bankAmount);
    }
  }

  double? get _typedNgn {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return v == null || !v.isFinite || v <= 0 ? null : v;
  }

  Future<void> _prepareBank() async {
    final ngn = _fixed ? null : _typedNgn;
    if (!_fixed && ngn == null) return;
    final back = _stage;
    _goTo(_AskStage.preparing);
    try {
      final d = await zlinkServiceOf(context).askBankPrepare(
        widget.id,
        amountNgn: ngn,
      );
      if (!mounted) return;
      _bank = d;
      _goTo(_AskStage.bankDetails);
      _startPolling(d['order_id'] as String);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.userMessage
          : "We couldn't get bank details. Try again.";
      if (back == _AskStage.bankAmount) {
        _goTo(_AskStage.bankAmount);
        setState(() => _error = message);
      } else {
        _goTo(_AskStage.bankFailed);
        setState(() => _error = message);
      }
    }
  }

  void _startPolling(String orderId) {
    final service = zlinkServiceOf(context);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final s = await service.askBankStatus(widget.id, orderId);
        if (!mounted) return;
        if (s == 'paid') {
          _poll?.cancel();
          HapticFeedback.mediumImpact();
          unawaited(SoundService.playZentSuccess());
          _goTo(_AskStage.bankPaid);
        } else if (s == 'failed') {
          _poll?.cancel();
          _goTo(_AskStage.bankFailed);
          setState(
            () => _error =
                "That transfer didn't go through. If money left your bank, "
                'it will be returned.',
          );
        }
      } catch (_) {}
    });
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$label copied',
            style: const TextStyle(fontFamily: 'Geist'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Frame ───────────────────────────────────────────────────────────────

  String get _title => switch (_stage) {
    _AskStage.loading || _AskStage.unavailable => 'Pay',
    _AskStage.method => 'Pay $_payee',
    _AskStage.amount || _AskStage.bankAmount => 'How much?',
    _AskStage.confirm => 'Confirm',
    _AskStage.country || _AskStage.preparing => 'Pay by bank',
    _AskStage.bankDetails => 'Make the transfer',
    _AskStage.bankFailed => 'Pay by bank',
    _AskStage.paid || _AskStage.bankPaid => '',
  };

  /// Close on the first step and once there's nothing to go back to; back
  /// everywhere else.
  bool get _closes =>
      _stage == _first ||
      const {
        _AskStage.loading,
        _AskStage.unavailable,
        // Going back would open a second bank order for the same money.
        _AskStage.bankDetails,
        _AskStage.paid,
        _AskStage.bankPaid,
      }.contains(_stage);

  void _back() {
    if (_closes) {
      Navigator.of(context).pop();
      return;
    }
    switch (_stage) {
      case _AskStage.amount:
        _goTo(_AskStage.method);
      case _AskStage.confirm:
        _goTo(_fixed ? _AskStage.method : _AskStage.amount);
      case _AskStage.country:
        _goTo(_AskStage.method);
      case _AskStage.bankAmount:
      case _AskStage.bankFailed:
        _goTo(_AskStage.country);
      default:
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    final sheetHeight = ((mq.size.height - keyboardInset) * 0.88).clamp(
      320.0,
      mq.size.height,
    );
    final busy = _stage == _AskStage.preparing || _paying;

    return PopScope(
      canPop: !busy,
      child: Padding(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: busy ? null : _back,
                        icon: Icon(
                          _closes
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                    duration: ZendMotion.stageIn,
                    reverseDuration: ZendMotion.stageOut,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, ?current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_stage),
                      child: _buildStage(zt),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(ZendTheme zt) => switch (_stage) {
    _AskStage.loading => const Center(child: ZendLoader(size: 28)),
    _AskStage.unavailable => _AskCentered(
      icon: PhosphorIconsRegular.warningCircle,
      title: _unavailable ?? 'This link is no longer collecting',
      body: _preview == null
          ? 'Check the link with the person who sent it.'
          : 'Ask $_payee to send a new one if you still need to pay.',
      action: PrimaryButton(
        label: 'Done',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    _AskStage.method => _buildMethod(zt),
    _AskStage.amount => _buildAmount(zt, bank: false),
    _AskStage.confirm => _buildConfirm(zt),
    _AskStage.country => _buildCountry(zt),
    _AskStage.bankAmount => _buildAmount(zt, bank: true),
    _AskStage.preparing => _AskCentered(
      loader: true,
      title: 'Getting bank details',
      body: 'This can take up to a minute.',
    ),
    _AskStage.bankDetails => _buildBankDetails(zt),
    _AskStage.bankFailed => _AskCentered(
      icon: PhosphorIconsRegular.warningCircle,
      title: "That didn't go through",
      body: _error,
      action: OutlineActionButton(label: 'Try again', onPressed: _prepareBank),
    ),
    _AskStage.paid => _buildPaid(zt, bank: false),
    _AskStage.bankPaid => _buildPaid(zt, bank: true),
  };

  // ── Steps ───────────────────────────────────────────────────────────────

  /// Who's asking, for what, and how much: the top of the first steps.
  Widget _askHeader(ZendTheme zt) {
    final memo = (_v['memo'] as String?)?.trim();
    return Column(
      children: [
        ZendAvatar(
          radius: 28,
          seed: _v['payee_zendtag'] as String? ?? _payee,
          initials: personInitial(
            displayName: _payee,
            handle: _v['payee_zendtag'] as String?,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _fixed ? '$_payee is asking for' : '$_payee is asking you to pay',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14,
            color: zt.textSecondary,
          ),
        ),
        if (_fixed) ...[
          const SizedBox(height: 4),
          Text(
            zlinkAmountLabel(_v),
            style: ZendTextStyles.tabularNumeric.copyWith(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
        ],
        if (memo != null && memo.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '“$memo”',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              height: 1.4,
              color: zt.textPrimary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMethod(ZendTheme zt) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _askHeader(zt),
        const SizedBox(height: 28),
        Text(
          'Pay with',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        _AskOption(
          icon: PhosphorIconsRegular.wallet,
          title: 'My Zend',
          subtitle: _balance > 0
              ? 'You have ${formatMoney(_balance)}'
              : 'Pay from your Zend balance',
          onTap: _balanceCovers ? _chooseZend : null,
        ),
        const SizedBox(height: 10),
        _AskOption(
          icon: PhosphorIconsRegular.bank,
          title: 'Bank transfer',
          subtitle: 'From your bank app. Goes straight to $_payee.',
          onTap: _chooseBank,
        ),
      ],
    );
  }

  Widget _buildAmount(ZendTheme zt, {required bool bank}) {
    final naira = bank || _entry.naira;
    final symbol = bank ? '₦' : _entry.symbol;
    final typed = bank ? (_typedNgn ?? 0) : _entry.usd(_amount.text);
    final max = (_v['max_amount_usd'] as num?)?.toDouble();
    final tooMuch =
        !bank && max != null && typed > 0 && _entry.usd(_amount.text) > max;
    final canContinue = typed > 0 && !tooMuch;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              children: [
                Text(
                  bank ? 'Amount to send $_payee' : 'Amount to pay $_payee',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      symbol,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    IntrinsicWidth(
                      child: TextField(
                        controller: _amount,
                        focusNode: _amountFocus,
                        inputFormatters: [AmountInputFormatter(naira: naira)],
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: !naira,
                        ),
                        style: ZendTextStyles.displayXl.copyWith(
                          color: zt.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: ZendTextStyles.displayXl.copyWith(
                            color: zt.textSecondary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  _AskInlineError(_error!)
                else if (tooMuch)
                  _AskInlineError('$_payee accepts up to ${formatMoney(max)}')
                else if (bank)
                  Text(
                    "You'll see the bank details next.",
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
            label: 'Continue',
            onPressed: !canContinue
                ? null
                : bank
                ? _prepareBank
                : () => _goTo(_AskStage.confirm),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirm(ZendTheme zt) {
    final memo = (_v['memo'] as String?)?.trim();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            children: [
              Center(
                child: Column(
                  children: [
                    Text(
                      'You pay',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: zt.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _zendAmountLabel,
                      style: ZendTextStyles.tabularNumeric.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _AskDetailRow(label: 'To', value: _payee),
              Divider(color: zt.border, height: 1),
              _AskDetailRow(label: 'From', value: 'Your Zend'),
              if (memo != null && memo.isNotEmpty) ...[
                Divider(color: zt.border, height: 1),
                _AskDetailRow(label: 'For', value: memo),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _AskInlineError(_error!),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: PrimaryButton(
            label: 'Pay $_zendAmountLabel',
            isLoading: _paying,
            onPressed: _paying ? null : _pay,
          ),
        ),
      ],
    );
  }

  Widget _buildCountry(ZendTheme zt) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        // Landing straight here (nothing in their Zend): show who's asking.
        if (_first == _AskStage.country) ...[
          _askHeader(zt),
          const SizedBox(height: 28),
        ],
        Text(
          'Where is your bank?',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        _AskOption(
          flag: ZendCountry.ng,
          title: 'Nigeria',
          subtitle: 'Bank transfer in naira',
          onTap: _chooseCountry,
        ),
        const SizedBox(height: 12),
        Text(
          'More countries soon.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 12,
            color: zt.textSecondary,
          ),
        ),
        if (_first == _AskStage.country && _balanceCovers) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _chooseZend,
              child: const Text('Pay from my Zend instead'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBankDetails(ZendTheme zt) {
    final d = _bank!;
    final ngn = formatNaira(((d['amount_ngn'] as num?) ?? 0).toDouble());
    final number = d['account_number'] as String? ?? '';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
                      ngn,
                      style: ZendTextStyles.tabularNumeric.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'It goes straight to $_payee',
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
              _AskDetailRow(label: 'Bank', value: d['bank_name'] as String? ?? ''),
              Divider(color: zt.border, height: 1),
              _AskDetailRow(
                label: 'Account number',
                value: number,
                monospace: true,
                onCopy: () => _copy(number, 'Account number'),
              ),
              Divider(color: zt.border, height: 1),
              _AskDetailRow(
                label: 'Account name',
                value: d['account_name'] as String? ?? '',
              ),
              Divider(color: zt.border, height: 1),
              _AskDetailRow(
                label: 'Amount',
                value: ngn,
                monospace: true,
                onCopy: () => _copy(
                  ((d['amount_ngn'] as num?) ?? 0).round().toString(),
                  'Amount',
                ),
              ),
              const SizedBox(height: 16),
              const _AskNotice(
                icon: PhosphorIconsRegular.warning,
                text:
                    'Send the exact amount from your own bank account. '
                    'A different amount can delay or fail the transfer.',
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ZendLoader(size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for your transfer',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: PrimaryButton(
            label: "I'll check back later",
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  /// Paid. By bank this is also the moment to show what Zend is.
  Widget _buildPaid(ZendTheme zt, {required bool bank}) {
    final label = bank
        ? formatNaira(((_bank?['amount_ngn'] as num?) ?? 0).toDouble())
        : _zendAmountLabel;
    final messageUserId = _messageUserId;
    final navigator = Navigator.of(context, rootNavigator: true);
    return _AskCentered(
      success: true,
      title: 'Paid!',
      body: bank
          ? '$label reached $_payee.\nNext time, pay anyone on Zend in a tap. '
                'Add money once and it stays in your Zend until you send it.'
          : '$label sent to $_payee',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bank) ...[
            OutlineActionButton(
              label: 'Add money to my Zend',
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(showAddCashSheet(navigator.context));
              },
            ),
            const SizedBox(height: 12),
          ] else if (messageUserId != null) ...[
            OutlineActionButton(
              label: 'Message $_payee',
              onPressed: () => _message(messageUserId),
            ),
            const SizedBox(height: 12),
          ],
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ── Pieces, matching Add cash and Bank send ──────────────────────────────────

/// A choice row: icon or country flag, title, subtitle, chevron. Greyed out
/// when [onTap] is null.
class _AskOption extends StatelessWidget {
  const _AskOption({
    this.icon,
    this.flag,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData? icon;
  final ZendCountry? flag;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZendRadii.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                if (flag != null)
                  ZendCountryFlag(country: flag!, size: 32)
                else
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
      ),
    );
  }
}

class _AskDetailRow extends StatelessWidget {
  const _AskDetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.onCopy,
  });

  final String label;
  final String value;
  final bool monospace;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
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
            const SizedBox(width: 16),
            const Spacer(),
            Flexible(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

class _AskNotice extends StatelessWidget {
  const _AskNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
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

class _AskInlineError extends StatelessWidget {
  const _AskInlineError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontFamily: 'Geist',
      fontSize: 13,
      color: ZendColors.destructive,
    ),
  );
}

/// A centred state: loading, a problem, or success (the green check that
/// Bank send uses), with an optional action pinned to the bottom.
class _AskCentered extends StatefulWidget {
  const _AskCentered({
    required this.title,
    this.icon,
    this.body,
    this.action,
    this.loader = false,
    this.success = false,
  });

  final String title;
  final IconData? icon;
  final String? body;
  final Widget? action;
  final bool loader;
  final bool success;

  @override
  State<_AskCentered> createState() => _AskCenteredState();
}

class _AskCenteredState extends State<_AskCentered>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.elasticOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.success) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final Widget mark = widget.loader
        ? const ZendLoader(size: 32)
        : widget.success
        ? ScaleTransition(
            scale: _scale,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: ZendColors.positive,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsRegular.check,
                color: Colors.white,
                size: 34,
              ),
            ),
          )
        : Icon(widget.icon, size: 44, color: zt.textSecondary);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mark,
                  const SizedBox(height: 20),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontWeight: FontWeight.w700,
                      fontSize: widget.success ? 34 : 20,
                      color: zt.textPrimary,
                    ),
                  ),
                  if (widget.body != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.body!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        height: 1.4,
                        color: zt.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (widget.action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: widget.action!,
          ),
      ],
    );
  }
}
