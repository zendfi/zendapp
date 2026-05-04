// Bank send stage widgets.
// ignore_for_file: library_private_types_in_public_api

part of 'bank_send_sheet.dart';

// ── Rail definitions ──────────────────────────────────────────────────────────

class _RailInfo {
  const _RailInfo({
    required this.rail,
    required this.country,
    required this.title,
    required this.subtitle,
  });
  final _BankSendRail rail;
  final ZendCountry country;
  final String title;
  final String subtitle;
}

const _kRails = [
  _RailInfo(
    rail: _BankSendRail.ngn,
    country: ZendCountry.ng,
    title: 'Nigeria',
    subtitle: 'GTBank, Access, Zenith, UBA and more',
  ),
  _RailInfo(
    rail: _BankSendRail.ach,
    country: ZendCountry.us,
    title: 'United States',
    subtitle: 'Chase, Bank of America, Wells Fargo and more',
  ),
  _RailInfo(
    rail: _BankSendRail.fp,
    country: ZendCountry.gb,
    title: 'United Kingdom (UK)',
    subtitle: 'Barclays, HSBC, Lloyds, Monzo and more',
  ),
  _RailInfo(
    rail: _BankSendRail.sepa,
    country: ZendCountry.eu,
    title: 'European Union (EU)',
    subtitle: 'Revolut, N26, Deutsche Bank and more',
  ),
];

// ── Rail Select ───────────────────────────────────────────────────────────────

class _RailSelectStage extends StatelessWidget {
  const _RailSelectStage({
    required this.amount,
    required this.onSelect,
  });
  final double amount;
  final void Function(_BankSendRail) onSelect;

  String get _amountStr => amount == amount.roundToDouble()
      ? '\$${amount.toStringAsFixed(0)}'
      : '\$${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send $_amountStr to',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your destination',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: _kRails.length,
              separatorBuilder: (_, i) =>
                  Divider(height: 1, color: zt.border),
              itemBuilder: (context, i) {
                final info = _kRails[i];
                return _RailTile(info: info, onTap: () => onSelect(info.rail));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({required this.info, required this.onTap});
  final _RailInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZendRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            ZendCountryFlag(country: info.country, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.subtitle,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
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

// ── NGN Bank Input ────────────────────────────────────────────────────────────

class _NgnBankInputStage extends StatefulWidget {
  const _NgnBankInputStage({
    required this.amount,
    required this.ngnRate,
    required this.selectedBank,
    required this.accountController,
    required this.errorMessage,
    required this.onSelectBank,
    required this.onContinue,
    required this.onBack,
  });
  final double amount;
  final double ngnRate;
  final Map<String, dynamic>? selectedBank;
  final TextEditingController accountController;
  final String? errorMessage;
  final VoidCallback onSelectBank;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  State<_NgnBankInputStage> createState() => _NgnBankInputStageState();
}

class _NgnBankInputStageState extends State<_NgnBankInputStage> {
  bool get _canContinue =>
      widget.selectedBank != null &&
      widget.accountController.text.trim().length >= 10;

  String get _fxPreview {
    if (widget.ngnRate <= 0 || widget.amount <= 0) return '';
    final ngn = widget.amount * widget.ngnRate;
    return '≈ ₦${_formatNgn(ngn)}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amountStr = widget.amount == widget.amount.roundToDouble()
        ? '\$${widget.amount.toStringAsFixed(0)}'
        : '\$${widget.amount.toStringAsFixed(2)}';

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nigerian bank',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    if (_fxPreview.isNotEmpty)
                      Text(
                        '$amountStr · $_fxPreview',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 12,
                          color: zt.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Bank selector button
          GestureDetector(
            onTap: widget.onSelectBank,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.lg),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.selectedBank?['name'] as String? ?? 'Select bank',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: widget.selectedBank != null
                            ? zt.textPrimary
                            : zt.textSecondary,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: zt.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
            Text(
              widget.errorMessage!,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: ZendColors.destructive,
              ),
            ),
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
            child: const Text(
              'Verify account',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank Picker (searchable full-stage list) ──────────────────────────────────

class _BankPickerStage extends StatefulWidget {
  const _BankPickerStage({
    required this.banks,
    required this.onSelect,
    required this.onBack,
  });
  final List<Map<String, dynamic>> banks;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onBack;

  @override
  State<_BankPickerStage> createState() => _BankPickerStageState();
}

class _BankPickerStageState extends State<_BankPickerStage> {
  final _searchController = TextEditingController();
  String _query = '';

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.banks;
    final q = _query.toLowerCase();
    return widget.banks
        .where((b) => (b['name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
              Text(
                'Select bank',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search banks...',
              prefixIcon: Icon(Icons.search, size: 20, color: zt.textSecondary),
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
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No banks found',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        color: zt.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, i) =>
                        Divider(height: 1, color: zt.border),
                    itemBuilder: (context, i) {
                      final bank = _filtered[i];
                      final name = bank['name'] as String? ?? '';
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            color: zt.textPrimary,
                          ),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            size: 18, color: zt.textSecondary),
                        onTap: () => widget.onSelect(bank),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Intl Account Stage ────────────────────────────────────────────────────────

class _IntlAccountStage extends StatelessWidget {
  const _IntlAccountStage({
    required this.rail,
    required this.savedAccounts,
    required this.onSelect,
    required this.onBack,
    required this.onAddAccount,
  });
  final _BankSendRail rail;
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
              Text(
                '${rail.currency} bank',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
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
                    Text(
                      'No saved accounts yet',
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          color: zt.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a bank account to get started',
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: zt.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: savedAccounts.length,
                separatorBuilder: (_, i) =>
                    Divider(height: 1, color: zt.border, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final acct = savedAccounts[i];
                  final label = acct['label'] as String? ?? 'Bank account';
                  final bankName = acct['bank_name'] as String? ?? '';
                  final last4 = acct['account_last4'] as String?;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                    title: Text(
                      label,
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary),
                    ),
                    subtitle: Text(
                      [
                        if (bankName.isNotEmpty) bankName,
                        if (last4 != null) '••••$last4',
                        rail.currency,
                      ].join(' · '),
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          color: zt.textSecondary),
                    ),
                    trailing: Icon(Icons.chevron_right, color: zt.textSecondary),
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

// ── Resolving Stage ───────────────────────────────────────────────────────────

class _ResolvingStage extends StatelessWidget {
  const _ResolvingStage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text(
            'Verifying...',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendTheme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirmation Stage ────────────────────────────────────────────────────────

class _ConfirmationStage extends StatelessWidget {
  const _ConfirmationStage({
    required this.rail,
    required this.amountUsdc,
    required this.fiatAmount,
    required this.accountName,
    required this.bankName,
    required this.accountNumberMasked,
    required this.onConfirm,
    required this.onBack,
  });
  final _BankSendRail rail;
  final double amountUsdc;
  final double? fiatAmount;
  final String accountName;
  final String bankName;
  final String accountNumberMasked;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  String get _fiatSymbol => switch (rail.currency) {
        'NGN' => '₦',
        'GBP' => '£',
        'EUR' => '€',
        _ => '\$',
      };

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
              Text(
                'Confirm transfer',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text(
                  amountStr,
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontStyle: FontStyle.italic,
                    fontSize: 48,
                    color: zt.textPrimary,
                  ),
                ),
                if (fiatAmount != null && fiatAmount! > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$_fiatSymbol${_formatFiat(fiatAmount!, rail.currency)} ${rail.currency}',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 15,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                if (accountNumberMasked.isNotEmpty) ...[
                  Divider(height: 20, color: zt.border),
                  _DetailRow(label: 'Account', value: accountNumberMasked, zt: zt),
                ],
                Divider(height: 20, color: zt.border),
                _DetailRow(label: 'You send', value: amountStr, zt: zt),
              ],
            ),
          ),
          const Spacer(),
          PrimaryButton(label: 'Enter PIN to send', onPressed: onConfirm),
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
  });
  final String label;
  final String value;
  final ZendTheme zt;

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
                color: zt.textPrimary)),
      ],
    );
  }
}

String _formatFiat(double value, String currency) {
  if (currency == 'NGN') return _formatNgn(value);
  return value.toStringAsFixed(2);
}

// ── PIN Stage — uses light keypad matching send_flow_sheet ────────────────────

class _PinStage extends StatelessWidget {
  const _PinStage({
    required this.amountUsdc,
    required this.rail,
    required this.pinDigits,
    required this.pinError,
    required this.shakeAnimation,
    required this.shakeController,
    required this.onKey,
    required this.onBack,
  });
  final double amountUsdc;
  final _BankSendRail rail;
  final String pinDigits;
  final String? pinError;
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  String get _amountStr => amountUsdc == amountUsdc.roundToDouble()
      ? '\$${amountUsdc.toStringAsFixed(0)}'
      : '\$${amountUsdc.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final compact = MediaQuery.of(context).size.height < 760;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Confirm with PIN',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sending $_amountStr to ${rail.currency} bank',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          SizedBox(height: compact ? 24 : 36),
          AnimatedBuilder(
            animation: shakeController,
            builder: (context, child) => Transform.translate(
              offset: Offset(shakeAnimation.value, 0),
              child: child,
            ),
            child: _LightPinDots(filledCount: pinDigits.length),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 20,
            child: pinError != null
                ? Text(
                    pinError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: ZendColors.destructive,
                    ),
                  )
                : null,
          ),
          const Spacer(),
          _LightPinKeypad(
            onTap: onKey,
            keyHeight: compact ? 56 : 64,
          ),
          SizedBox(height: compact ? 4 : 12),
        ],
      ),
    );
  }
}

// Light PIN dots — matches send_flow_sheet style
class _LightPinDots extends StatelessWidget {
  const _LightPinDots({required this.filledCount});
  final int filledCount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
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

// Light PIN keypad — same style as send_flow_sheet._PinKeypad
class _LightPinKeypad extends StatelessWidget {
  const _LightPinKeypad({required this.onTap, required this.keyHeight});
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
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == 2 ? 0 : 10,
                      bottom: row == 3 ? 0 : 12,
                    ),
                    child: keys[row * 3 + col].isEmpty
                        ? SizedBox(height: keyHeight)
                        : _LightPinKey(
                            label: keys[row * 3 + col],
                            keyHeight: keyHeight,
                            onTap: () => onTap(keys[row * 3 + col]),
                          ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LightPinKey extends StatefulWidget {
  const _LightPinKey({
    required this.label,
    required this.onTap,
    required this.keyHeight,
  });
  final String label;
  final VoidCallback onTap;
  final double keyHeight;

  @override
  State<_LightPinKey> createState() => _LightPinKeyState();
}

class _LightPinKeyState extends State<_LightPinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final display = widget.label == 'del' ? '⌫' : widget.label;
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
            child: Text(
              display,
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

// ── Processing Stage ──────────────────────────────────────────────────────────

class _ProcessingStage extends StatelessWidget {
  const _ProcessingStage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text(
            'Sending to your bank...',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendTheme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Success Stage ─────────────────────────────────────────────────────────────

class _SuccessStage extends StatefulWidget {
  const _SuccessStage({
    required this.rail,
    required this.amountUsdc,
    required this.fiatAmount,
    required this.bankName,
    required this.onDone,
  });
  final _BankSendRail rail;
  final double amountUsdc;
  final double? fiatAmount;
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

  String get _fiatSymbol => switch (widget.rail.currency) {
        'NGN' => '₦',
        'GBP' => '£',
        'EUR' => '€',
        _ => '\$',
      };

  String get _subtitle {
    if (widget.fiatAmount != null && widget.fiatAmount! > 0) {
      final fiatStr = widget.rail.currency == 'NGN'
          ? '$_fiatSymbol${_formatNgn(widget.fiatAmount!)}'
          : '$_fiatSymbol${widget.fiatAmount!.toStringAsFixed(2)}';
      return '$fiatStr on its way to ${widget.bankName}';
    }
    final amtStr = widget.amountUsdc == widget.amountUsdc.roundToDouble()
        ? '\$${widget.amountUsdc.toStringAsFixed(0)}'
        : '\$${widget.amountUsdc.toStringAsFixed(2)}';
    return '$amtStr on its way to ${widget.bankName}';
  }

  String get _eta => widget.rail == _BankSendRail.ngn
      ? 'Usually arrives within minutes'
      : 'Usually arrives within 1–2 business days';

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
                child: const Icon(Icons.check, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'On its way!',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 40,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 15, color: zt.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              _eta,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary.withValues(alpha: 0.7),
              ),
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

// ── Error Stage ───────────────────────────────────────────────────────────────

class _ErrorStage extends StatelessWidget {
  const _ErrorStage({
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
            Text(
              'Oops',
              style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 32,
                  color: zt.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 15, color: zt.textSecondary),
            ),
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
    required this.rail,
    required this.onBack,
    required this.onSaved,
  });
  final _BankSendRail rail;
  final VoidCallback onBack;
  final void Function(Map<String, dynamic>) onSaved;

  @override
  State<_AddIntlAccountStage> createState() => _AddIntlAccountStageState();
}

class _AddIntlAccountStageState extends State<_AddIntlAccountStage> {
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
    switch (widget.rail) {
      case _BankSendRail.ach:
        return _routingController.text.trim().length == 9 &&
            _accountController.text.trim().length >= 4;
      case _BankSendRail.fp:
        return _sortCodeController.text.trim().length >= 6 &&
            _fpAccountController.text.trim().length >= 8;
      case _BankSendRail.sepa:
        return _ibanController.text.trim().length >= 15;
      default:
        return false;
    }
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final model = ZendScope.of(context);
      Map<String, dynamic> accountDetails;
      switch (widget.rail) {
        case _BankSendRail.ach:
          accountDetails = {
            'routing_number': _routingController.text.trim(),
            'account_number': _accountController.text.trim(),
          };
        case _BankSendRail.fp:
          accountDetails = {
            'sort_code': _sortCodeController.text.trim().replaceAll('-', ''),
            'account_number': _fpAccountController.text.trim(),
          };
        case _BankSendRail.sepa:
          accountDetails = {
            'iban': _ibanController.text.trim().toUpperCase(),
          };
        default:
          accountDetails = {};
      }
      final result = await model.walletService.apiClient.addIntlBankAccount({
        'label':
            '${_ownerController.text.trim()} (${widget.rail.currency})',
        'currency': widget.rail.bridgeCurrency,
        'payment_rail': widget.rail.bridgeRail,
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
              Text(
                'Add ${widget.rail.currency} account',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  if (widget.rail == _BankSendRail.ach) ...[
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
                  ] else if (widget.rail == _BankSendRail.fp) ...[
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
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.destructive),
                    ),
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
              child: const Text(
                'Save account',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
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
        Text(
          label,
          style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: zt.textSecondary),
        ),
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

// ── Shared helpers ────────────────────────────────────────────────────────────

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
