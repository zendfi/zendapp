part of 'bank_send_sheet.dart';

class _RailSelectStage extends StatelessWidget {
  const _RailSelectStage({super.key, required this.onSelect});
  final void Function(_BankSendRail) onSelect;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send to bank',
              style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary)),
          const SizedBox(height: 6),
          Text('Choose where to send',
              style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
          const SizedBox(height: 24),
          _RailCard(
            emoji: '🇳🇬',
            title: 'Nigerian bank',
            subtitle: 'GTBank, Access, Zenith and more',
            onTap: () => onSelect(_BankSendRail.ngn),
          ),
          const SizedBox(height: 12),
          _RailCard(
            emoji: '🌍',
            title: 'International bank',
            subtitle: 'US, UK, Europe — ACH, Faster Payments, SEPA',
            onTap: () => onSelect(_BankSendRail.intl),
          ),
        ],
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.xxl),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: zt.bgPrimary,
                borderRadius: BorderRadius.circular(ZendRadii.md),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          color: zt.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: zt.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _NgnBankInputStage extends StatefulWidget {
  const _NgnBankInputStage({
    super.key,
    required this.banks,
    required this.selectedBank,
    required this.accountController,
    required this.errorMessage,
    required this.onBankSelected,
    required this.onContinue,
    required this.onBack,
  });
  final List<Map<String, dynamic>> banks;
  final Map<String, dynamic>? selectedBank;
  final TextEditingController accountController;
  final String? errorMessage;
  final void Function(Map<String, dynamic>) onBankSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  State<_NgnBankInputStage> createState() => _NgnBankInputStageState();
}

class _NgnBankInputStageState extends State<_NgnBankInputStage> {
  bool get _canContinue =>
      widget.selectedBank != null &&
      widget.accountController.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Text('Nigerian bank',
                  style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          // Bank picker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, dynamic>>(
                value: widget.selectedBank,
                hint: Text('Select bank',
                    style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: zt.textSecondary)),
                isExpanded: true,
                dropdownColor: zt.bgSecondary,
                icon: Icon(Icons.keyboard_arrow_down, color: zt.textSecondary),
                items: widget.banks.map((bank) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: bank,
                    child: Text(bank['name'] as String? ?? '',
                        style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            color: zt.textPrimary)),
                  );
                }).toList(),
                onChanged: (b) {
                  if (b != null) widget.onBankSelected(b);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Account number
          TextField(
            controller: widget.accountController,
            keyboardType: TextInputType.number,
            maxLength: 10,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Account number',
              counterText: '',
              filled: true,
              fillColor: zt.bgSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZendRadii.lg),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(widget.errorMessage!,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: ZendColors.destructive)),
          ],
          const Spacer(),
          ElevatedButton(
            onPressed: _canContinue ? widget.onContinue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: ZendTheme.of(context).accent,
              foregroundColor: ZendColors.textOnDeep,
              disabledBackgroundColor: ZendTheme.of(context).border,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZendRadii.lg)),
            ),
            child: const Text('Verify account',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _IntlAccountStage extends StatelessWidget {
  const _IntlAccountStage({
    super.key,
    required this.savedAccounts,
    required this.onSelect,
    required this.onBack,
    required this.onAddAccount,
  });
  final List<Map<String, dynamic>> savedAccounts;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onBack;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Text('International bank',
                  style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          if (savedAccounts.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_outlined,
                        size: 48, color: zt.textSecondary),
                    const SizedBox(height: 16),
                    Text('No saved accounts yet',
                        style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            color: zt.textSecondary)),
                    const SizedBox(height: 8),
                    Text('Add a bank account to get started',
                        style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            color: zt.textSecondary)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: savedAccounts.length,
                separatorBuilder: (_, i) => Divider(
                    height: 1, color: zt.border, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final acct = savedAccounts[i];
                  final label = acct['label'] as String? ?? 'Bank account';
                  final bankName = acct['bank_name'] as String? ?? '';
                  final last4 = acct['account_last4'] as String?;
                  final currency =
                      (acct['currency'] as String? ?? 'usd').toUpperCase();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: zt.bgSecondary,
                        borderRadius: BorderRadius.circular(ZendRadii.md),
                      ),
                      child: Icon(Icons.account_balance_outlined,
                          size: 20, color: zt.textSecondary),
                    ),
                    title: Text(label,
                        style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: zt.textPrimary)),
                    subtitle: Text(
                        [
                          if (bankName.isNotEmpty) bankName,
                          if (last4 != null) '••••\$last4',
                          currency,
                        ].join(' · '),
                        style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 12,
                            color: zt.textSecondary)),
                    trailing:
                        Icon(Icons.chevron_right, color: zt.textSecondary),
                    onTap: () => onSelect(acct),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          OutlineActionButton(
            label: 'Add new account',
            onPressed: onAddAccount,
          ),
        ],
      ),
    );
  }
}

class _ResolvingStage extends StatelessWidget {
  const _ResolvingStage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text('Verifying...',
              style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: ZendTheme.of(context).textSecondary)),
        ],
      ),
    );
  }
}

class _AmountInputStage extends StatefulWidget {
  const _AmountInputStage({
    super.key,
    required this.rail,
    required this.accountName,
    required this.bankName,
    required this.accountNumberMasked,
    required this.ngnRate,
    required this.fiatCurrency,
    required this.amountController,
    required this.onContinue,
    required this.onBack,
  });
  final _BankSendRail rail;
  final String? accountName;
  final String? bankName;
  final String? accountNumberMasked;
  final double ngnRate;
  final String fiatCurrency;
  final TextEditingController amountController;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  State<_AmountInputStage> createState() => _AmountInputStageState();
}

class _AmountInputStageState extends State<_AmountInputStage> {
  double? _parsedAmount;

  String get _fxPreview {
    if (_parsedAmount == null || _parsedAmount! <= 0) return '';
    if (widget.rail == _BankSendRail.ngn && widget.ngnRate > 0) {
      final ngn = _parsedAmount! * widget.ngnRate;
      return '≈ ₦${_formatNgn(ngn)}';
    }
    return '';
  }

  bool get _canContinue => _parsedAmount != null && _parsedAmount! >= 0.5;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('How much?',
                    style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Recipient info card
          if (widget.accountName != null || widget.bankName != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.lg),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ZendColors.positive.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: ZendColors.positive, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.accountName != null)
                          Text(widget.accountName!,
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: zt.textPrimary)),
                        if (widget.bankName != null ||
                            widget.accountNumberMasked != null)
                          Text(
                              [
                                if (widget.bankName != null) widget.bankName!,
                                if (widget.accountNumberMasked != null)
                                  widget.accountNumberMasked!,
                              ].join(' · '),
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 12,
                                  color: zt.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Amount field
          TextField(
            controller: widget.amountController,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              setState(() => _parsedAmount = double.tryParse(v.trim()));
            },
            style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 36,
                fontStyle: FontStyle.italic,
                color: zt.textPrimary),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 36,
                  fontStyle: FontStyle.italic,
                  color: zt.textSecondary),
              hintText: '0.00',
              hintStyle: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 36,
                  fontStyle: FontStyle.italic,
                  color: zt.textSecondary.withValues(alpha: 0.4)),
              filled: false,
              border: InputBorder.none,
            ),
          ),
          if (_fxPreview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_fxPreview,
                style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 14,
                    color: zt.textSecondary)),
          ],
          const Spacer(),
          ElevatedButton(
            onPressed: _canContinue ? widget.onContinue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: ZendTheme.of(context).accent,
              foregroundColor: ZendColors.textOnDeep,
              disabledBackgroundColor: ZendTheme.of(context).border,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZendRadii.lg)),
            ),
            child: const Text('Continue',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationStage extends StatelessWidget {
  const _ConfirmationStage({
    super.key,
    required this.rail,
    required this.amountUsdc,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.accountName,
    required this.bankName,
    required this.accountNumberMasked,
    required this.onConfirm,
    required this.onBack,
  });
  final _BankSendRail rail;
  final double amountUsdc;
  final double? fiatAmount;
  final String fiatCurrency;
  final String accountName;
  final String bankName;
  final String accountNumberMasked;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  String get _fiatSymbol {
    switch (fiatCurrency.toUpperCase()) {
      case 'NGN': return '₦';
      case 'GBP': return '£';
      case 'EUR': return '€';
      default: return '\$';
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amountStr = amountUsdc == amountUsdc.roundToDouble()
        ? '\$${amountUsdc.toStringAsFixed(0)}'
        : '\$${amountUsdc.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Text('Confirm transfer',
                  style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary)),
            ],
          ),
          const SizedBox(height: 24),
          // Amount hero
          Center(
            child: Column(
              children: [
                Text(amountStr,
                    style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontStyle: FontStyle.italic,
                        fontSize: 48,
                        color: zt.textPrimary)),
                if (fiatAmount != null && fiatAmount! > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                      '$_fiatSymbol${_formatFiat(fiatAmount!, fiatCurrency)} ${fiatCurrency.toUpperCase()}',
                      style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 15,
                          color: zt.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Details card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.xxl),
            ),
            child: Column(
              children: [
                _DetailRow(label: 'To', value: accountName, zt: zt),
                Divider(height: 20, color: zt.border),
                _DetailRow(label: 'Bank', value: bankName, zt: zt),
                Divider(height: 20, color: zt.border),
                _DetailRow(
                    label: 'Account',
                    value: accountNumberMasked,
                    zt: zt),
                Divider(height: 20, color: zt.border),
                _DetailRow(
                    label: 'You send',
                    value: '$amountStr USDC',
                    zt: zt,
                    valueColor: zt.textPrimary),
              ],
            ),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Enter PIN to send',
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.zt,
    this.valueColor,
  });
  final String label;
  final String value;
  final ZendTheme zt;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
        Text(value,
            style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? zt.textPrimary)),
      ],
    );
  }
}

String _formatFiat(double value, String currency) {
  if (currency.toUpperCase() == 'NGN') {
    return _formatNgn(value);
  }
  return value.toStringAsFixed(2);
}

class _PinStage extends StatelessWidget {
  const _PinStage({
    super.key,
    required this.amountUsdc,
    required this.fiatCurrency,
    required this.pinDigits,
    required this.pinError,
    required this.shakeAnimation,
    required this.shakeController,
    required this.onKey,
    required this.onBack,
  });
  final double amountUsdc;
  final String fiatCurrency;
  final String pinDigits;
  final String? pinError;
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  String get _amountStr {
    return amountUsdc == amountUsdc.roundToDouble()
        ? '\$${amountUsdc.toStringAsFixed(0)}'
        : '\$${amountUsdc.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;
    return Container(
      color: ZendColors.bgDeep,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: onBack,
                child: const Icon(Icons.arrow_back,
                    color: ZendColors.textOnDeep, size: 22),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Confirm with PIN',
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 22,
                color: ZendColors.textOnDeep,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sending $_amountStr to bank',
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: Color(0x99E8F4EC),
              ),
            ),
            SizedBox(height: compact ? 24 : 36),
            AnimatedBuilder(
              animation: shakeController,
              builder: (context, child) => Transform.translate(
                offset: Offset(shakeAnimation.value, 0),
                child: child,
              ),
              child: _BankPinDots(filledCount: pinDigits.length),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 20,
              child: pinError != null
                  ? Text(pinError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.destructive))
                  : null,
            ),
            const Spacer(),
            _BankPinKeypad(
              onTap: onKey,
              keyHeight: compact ? 62 : 72,
            ),
            SizedBox(height: compact ? 4 : 12),
          ],
        ),
      ),
    );
  }
}

class _BankPinDots extends StatelessWidget {
  const _BankPinDots({required this.filledCount});
  final int filledCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? ZendColors.accentPop : Colors.transparent,
              border: Border.all(
                color: filled
                    ? ZendColors.accentPop
                    : const Color(0x66E8F4EC),
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _BankPinKeypad extends StatelessWidget {
  const _BankPinKeypad({required this.onTap, required this.keyHeight});
  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '',  '0', 'del',
    ];
    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var col = 0; col < 3; col++)
                _BankPinKey(
                  label: keys[row * 3 + col],
                  onTap: onTap,
                  height: keyHeight,
                ),
            ],
          ),
          if (row < 3) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _BankPinKey extends StatefulWidget {
  const _BankPinKey({
    required this.label,
    required this.onTap,
    required this.height,
  });
  final String label;
  final ValueChanged<String> onTap;
  final double height;

  @override
  State<_BankPinKey> createState() => _BankPinKeyState();
}

class _BankPinKeyState extends State<_BankPinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) {
      return SizedBox(width: 80, height: widget.height);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onTap(widget.label);
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        scale: _pressed ? 0.92 : 1.0,
        child: SizedBox(
          width: 80,
          height: widget.height,
          child: Center(
            child: widget.label == 'del'
                ? const Icon(Icons.backspace_outlined,
                    color: ZendColors.textOnDeep, size: 22)
                : Text(widget.label,
                    style: const TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: ZendColors.textOnDeep)),
          ),
        ),
      ),
    );
  }
}

class _ProcessingStage extends StatelessWidget {
  const _ProcessingStage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text('Sending to your bank...',
              style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: ZendTheme.of(context).textSecondary)),
        ],
      ),
    );
  }
}

class _SuccessStage extends StatefulWidget {
  const _SuccessStage({
    super.key,
    required this.rail,
    required this.amountUsdc,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.bankName,
    required this.onDone,
  });
  final _BankSendRail rail;
  final double amountUsdc;
  final double? fiatAmount;
  final String fiatCurrency;
  final String bankName;
  final VoidCallback onDone;

  @override
  State<_SuccessStage> createState() => _SuccessStageState();
}

class _SuccessStageState extends State<_SuccessStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _fiatSymbol {
    switch (widget.fiatCurrency.toUpperCase()) {
      case 'NGN': return '₦';
      case 'GBP': return '£';
      case 'EUR': return '€';
      default: return '\$';
    }
  }

  String get _subtitle {
    if (widget.fiatAmount != null && widget.fiatAmount! > 0) {
      final fiatStr = widget.fiatCurrency.toUpperCase() == 'NGN'
          ? '$_fiatSymbol${_formatNgn(widget.fiatAmount!)}'
          : '$_fiatSymbol${widget.fiatAmount!.toStringAsFixed(2)}';
      return '$fiatStr on its way to ${widget.bankName}';
    }
    final amtStr = widget.amountUsdc == widget.amountUsdc.roundToDouble()
        ? '\$${widget.amountUsdc.toStringAsFixed(0)}'
        : '\$${widget.amountUsdc.toStringAsFixed(2)}';
    return '$amtStr on its way to ${widget.bankName}';
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
              scale: _scale,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: ZendColors.positive, shape: BoxShape.circle),
                child:
                    const Icon(Icons.check, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text('On its way!',
                style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontStyle: FontStyle.italic,
                    fontSize: 40,
                    color: zt.textPrimary)),
            const SizedBox(height: 8),
            Text(_subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: zt.textSecondary)),
            const SizedBox(height: 6),
            Text(
              widget.rail == _BankSendRail.ngn
                  ? 'Usually arrives within minutes'
                  : 'Usually arrives within 1–2 business days',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: zt.textSecondary.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Done', onPressed: widget.onDone),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStage extends StatelessWidget {
  const _ErrorStage({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: ZendColors.destructive, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Oops',
                style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 32,
                    color: zt.textPrimary)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: zt.textSecondary)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Try again', onPressed: onRetry),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(label: 'Cancel', onPressed: onCancel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add International Account Stage ──────────────────────────────────────────

class _AddIntlAccountStage extends StatefulWidget {
  const _AddIntlAccountStage({
    super.key,
    required this.onBack,
    required this.onSaved,
  });
  final VoidCallback onBack;
  final void Function(Map<String, dynamic>) onSaved;

  @override
  State<_AddIntlAccountStage> createState() => _AddIntlAccountStageState();
}

class _AddIntlAccountStageState extends State<_AddIntlAccountStage> {
  String _currency = 'usd';
  String _rail = 'ach';

  final _ownerController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _routingController = TextEditingController();
  final _accountController = TextEditingController();
  final _sortCodeController = TextEditingController();
  final _fpAccountController = TextEditingController();
  final _ibanController = TextEditingController();

  bool _saving = false;
  String? _errorMessage;

  bool get _canSave {
    if (_ownerController.text.trim().isEmpty) return false;
    switch (_rail) {
      case 'ach':
        return _routingController.text.trim().length == 9 &&
            _accountController.text.trim().length >= 4;
      case 'faster_payments':
        return _sortCodeController.text.trim().length >= 6 &&
            _fpAccountController.text.trim().length >= 8;
      case 'sepa':
        return _ibanController.text.trim().length >= 15;
    }
    return false;
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() { _saving = true; _errorMessage = null; });
    try {
      final model = ZendScope.of(context);
      Map<String, dynamic> accountDetails;
      switch (_rail) {
        case 'ach':
          accountDetails = {
            'routing_number': _routingController.text.trim(),
            'account_number': _accountController.text.trim(),
          };
        case 'faster_payments':
          accountDetails = {
            'sort_code': _sortCodeController.text.trim().replaceAll('-', ''),
            'account_number': _fpAccountController.text.trim(),
          };
        case 'sepa':
          accountDetails = {'iban': _ibanController.text.trim().toUpperCase()};
        default:
          accountDetails = {};
      }
      final result = await model.walletService.apiClient.addIntlBankAccount({
        'label': '${_ownerController.text.trim()} (${_currency.toUpperCase()})',
        'currency': _currency,
        'payment_rail': _rail,
        'account_owner_name': _ownerController.text.trim(),
        'account_type': 'individual',
        if (_bankNameController.text.trim().isNotEmpty)
          'bank_name': _bankNameController.text.trim(),
        'account_details': accountDetails,
        'is_default': false,
      });
      if (!mounted) return;
      widget.onSaved(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'Could not add account. Please check the details.';
      });
    }
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _bankNameController.dispose();
    _routingController.dispose();
    _accountController.dispose();
    _sortCodeController.dispose();
    _fpAccountController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Text('Add bank account',
                  style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Currency selector
                  Row(
                    children: [
                      for (final (code, label, flag, railLabel) in [
                        ('usd', 'USD', '🇺🇸', 'ACH'),
                        ('gbp', 'GBP', '🇬🇧', 'Faster Payments'),
                        ('eur', 'EUR', '🇪🇺', 'SEPA'),
                      ])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _currency = code;
                              _rail = switch (code) {
                                'usd' => 'ach',
                                'gbp' => 'faster_payments',
                                _ => 'sepa',
                              };
                            }),
                            child: Container(
                              margin: EdgeInsets.only(
                                  right: code == 'eur' ? 0 : 8),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: _currency == code
                                    ? zt.accent.withValues(alpha: 0.12)
                                    : zt.bgSecondary,
                                borderRadius:
                                    BorderRadius.circular(ZendRadii.lg),
                                border: _currency == code
                                    ? Border.all(color: zt.accent, width: 1.5)
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Text(flag,
                                      style: const TextStyle(fontSize: 20)),
                                  const SizedBox(height: 4),
                                  Text(label,
                                      style: TextStyle(
                                          fontFamily: 'DMMono',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _currency == code
                                              ? zt.accent
                                              : zt.textPrimary)),
                                  Text(railLabel,
                                      style: TextStyle(
                                          fontFamily: 'DMSans',
                                          fontSize: 10,
                                          color: zt.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _FormField(
                    controller: _ownerController,
                    label: 'Account holder name',
                    hint: 'Full legal name',
                    onChanged: (_) => setState(() {}),
                    zt: zt,
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _bankNameController,
                    label: 'Bank name (optional)',
                    hint: 'e.g. Chase, Barclays',
                    onChanged: (_) => setState(() {}),
                    zt: zt,
                  ),
                  const SizedBox(height: 20),
                  if (_rail == 'ach') ...[
                    _FormField(
                      controller: _routingController,
                      label: 'Routing number',
                      hint: '9-digit ABA routing number',
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      onChanged: (_) => setState(() {}),
                      zt: zt,
                    ),
                    const SizedBox(height: 12),
                    _FormField(
                      controller: _accountController,
                      label: 'Account number',
                      hint: 'Checking or savings account number',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      zt: zt,
                    ),
                  ] else if (_rail == 'faster_payments') ...[
                    _FormField(
                      controller: _sortCodeController,
                      label: 'Sort code',
                      hint: '00-00-00',
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      onChanged: (_) => setState(() {}),
                      zt: zt,
                    ),
                    const SizedBox(height: 12),
                    _FormField(
                      controller: _fpAccountController,
                      label: 'Account number',
                      hint: '8-digit account number',
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      onChanged: (_) => setState(() {}),
                      zt: zt,
                    ),
                  ] else ...[
                    _FormField(
                      controller: _ibanController,
                      label: 'IBAN',
                      hint: 'e.g. DE89370400440532013000',
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      zt: zt,
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!,
                        style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            color: ZendColors.destructive)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          if (_saving)
            const Center(child: ZendLoader(size: 28))
          else
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZendTheme.of(context).accent,
                foregroundColor: ZendColors.textOnDeep,
                disabledBackgroundColor: ZendTheme.of(context).border,
                elevation: 0,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.lg)),
              ),
              child: const Text('Save account',
                  style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    required this.zt,
    this.keyboardType,
    this.maxLength,
    this.textCapitalization = TextCapitalization.words,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final ZendTheme zt;
  final TextInputType? keyboardType;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: zt.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            filled: true,
            fillColor: zt.bgSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ZendRadii.lg),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}


String _formatNgn(double value) {
  final rounded = value.round();
  final text = rounded.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final indexFromEnd = text.length - i;
    buffer.write(text[i]);
    if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
