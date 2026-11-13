part of 'zlink_sheets.dart';

/// Paying an ask link by bank transfer, for someone with nothing in their
/// Zend yet. They pick their country, the amount (when the link leaves it
/// open), and get bank details. Their transfer goes straight to the link's
/// owner; it never passes through their own balance. Once it lands, the sheet
/// says so and offers what they can do next with Zend.
enum _BankStage { country, amount, preparing, details, paid, failed }

class _AskBankPay extends StatefulWidget {
  const _AskBankPay({
    required this.id,
    required this.preview,
    required this.canPayFromBalance,
    required this.onUseBalance,
  });
  final String id;
  final Map<String, dynamic> preview;

  /// Whether to offer "Pay from my Zend" instead.
  final bool canPayFromBalance;
  final VoidCallback onUseBalance;

  @override
  State<_AskBankPay> createState() => _AskBankPayState();
}

class _AskBankPayState extends State<_AskBankPay> {
  _BankStage _stage = _BankStage.country;
  final _amount = TextEditingController();
  Map<String, dynamic>? _details;
  String? _error;
  Timer? _poll;

  String get _payee => widget.preview['payee_name'] as String? ?? 'them';
  bool get _fixed => widget.preview['amount_usd'] != null;

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    super.dispose();
  }

  double? get _typedNgn {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return v == null || !v.isFinite || v <= 0 ? null : v;
  }

  void _pickCountry() =>
      setState(() => _stage = _fixed ? _BankStage.preparing : _BankStage.amount);

  Future<void> _prepare() async {
    final ngn = _fixed ? null : _typedNgn;
    if (!_fixed && ngn == null) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    setState(() {
      _stage = _BankStage.preparing;
      _error = null;
    });
    try {
      final d = await zlinkServiceOf(context).askBankPrepare(
        widget.id,
        amountNgn: ngn,
      );
      if (!mounted) return;
      setState(() {
        _details = d;
        _stage = _BankStage.details;
      });
      _startPolling(d['order_id'] as String);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _stage = _fixed ? _BankStage.failed : _BankStage.amount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "We couldn't get bank details. Try again.";
        _stage = _fixed ? _BankStage.failed : _BankStage.amount;
      });
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
          setState(() => _stage = _BankStage.paid);
        } else if (s == 'failed') {
          _poll?.cancel();
          setState(() {
            _error = "That transfer didn't go through. If money left your "
                'bank, it will be returned.';
            _stage = _BankStage.failed;
          });
        }
      } catch (_) {}
    });
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: switch (_stage) {
        _BankStage.country => _countryStep(),
        _BankStage.amount => _amountStep(),
        _BankStage.preparing => _SheetFrame(
          icon: PhosphorIconsRegular.bank,
          title: 'Getting bank details',
          body: 'This can take up to a minute.',
          action: const ZendLoader(size: 28),
        ),
        _BankStage.details => _detailsStep(),
        _BankStage.paid => _paidStep(),
        _BankStage.failed => _SheetFrame(
          icon: PhosphorIconsRegular.warningCircle,
          title: "That didn't go through",
          body: _error,
          action: PrimaryButton(label: 'Try again', onPressed: _prepare),
        ),
      },
    );
  }

  Widget _useBalanceLink() => widget.canPayFromBalance
      ? TextButton(
          onPressed: widget.onUseBalance,
          child: const Text('Pay from my Zend instead'),
        )
      : const SizedBox.shrink();

  Widget _countryStep() {
    final zt = ZendTheme.of(context);
    return _SheetFrame(
      icon: PhosphorIconsRegular.bank,
      title: _fixed
          ? 'Pay $_payee ${zlinkAmountLabel(widget.preview)}'
          : 'Pay $_payee',
      body: [
        widget.preview['memo'] as String?,
        'Pay from your bank app. It goes straight to $_payee.',
      ].whereType<String>().join('\n'),
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Where is your bank?',
            style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary),
          ),
          const SizedBox(height: 8),
          Material(
            color: zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.lg),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZendRadii.lg),
              ),
              leading: const Text('🇳🇬', style: TextStyle(fontSize: 24)),
              title: const Text('Nigeria'),
              subtitle: const Text('Bank transfer in naira'),
              trailing: const Icon(PhosphorIconsRegular.caretRight),
              onTap: _fixed ? _prepare : _pickCountry,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'More countries soon.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              color: zt.textSecondary,
            ),
          ),
          _useBalanceLink(),
        ],
      ),
    );
  }

  Widget _amountStep() => _SheetFrame(
    icon: PhosphorIconsRegular.bank,
    title: 'How much to send $_payee?',
    body: _error,
    action: Column(
      children: [
        TextField(
          controller: _amount,
          autofocus: true,
          inputFormatters: const [AmountInputFormatter(naira: true)],
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Amount', prefixText: '₦'),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Continue',
          onPressed: _typedNgn == null ? null : _prepare,
        ),
      ],
    ),
  );

  Widget _detailsStep() {
    final zt = ZendTheme.of(context);
    final d = _details!;
    final ngn = formatNaira(((d['amount_ngn'] as num?) ?? 0).toDouble());
    Widget row(String label, String value, {bool copy = false}) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: zt.textPrimary,
        ),
      ),
      trailing: copy
          ? IconButton(
              icon: Icon(PhosphorIconsRegular.copy, color: zt.accent),
              onPressed: () => _copy(value, label),
            )
          : null,
    );
    return _SheetFrame(
      icon: PhosphorIconsRegular.bank,
      title: 'Transfer exactly $ngn',
      body: 'From your bank app. It goes straight to $_payee.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Bank', d['bank_name'] as String? ?? ''),
          row('Account number', d['account_number'] as String? ?? '', copy: true),
          row('Account name', d['account_name'] as String? ?? ''),
          row('Amount', ngn, copy: true),
          const SizedBox(height: 12),
          Text(
            'Send the exact amount. A different amount can delay the transfer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ZendLoader(size: 16),
              const SizedBox(width: 8),
              Text(
                'Waiting for your transfer',
                style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: "I'll check back later",
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// The moment to show what Zend is: the payment worked, and the same
  /// account can now hold, send and receive money.
  Widget _paidStep() {
    final ngn = formatNaira(((_details?['amount_ngn'] as num?) ?? 0).toDouble());
    final navigator = Navigator.of(context, rootNavigator: true);
    return _SheetFrame(
      icon: PhosphorIconsRegular.checkCircle,
      title: '$ngn reached $_payee',
      body: 'Next time, pay anyone on Zend in a tap. Add money once and it '
          'stays in your Zend until you send it.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlineActionButton(
            label: 'Add money to my Zend',
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(showAddCashSheet(navigator.context));
            },
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
