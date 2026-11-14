import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_format.dart';
import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

/// Names for the currency list. Anything Zend has a rate for but isn't named
/// here still appears, by its code.
const kCurrencyNames = <String, String>{
  'USD': 'US dollar', 'EUR': 'Euro', 'GBP': 'British pound',
  'NGN': 'Nigerian naira', 'GHS': 'Ghanaian cedi', 'KES': 'Kenyan shilling',
  'ZAR': 'South African rand', 'EGP': 'Egyptian pound', 'MAD': 'Moroccan dirham',
  'TZS': 'Tanzanian shilling', 'UGX': 'Ugandan shilling', 'RWF': 'Rwandan franc',
  'ETB': 'Ethiopian birr', 'ZMW': 'Zambian kwacha', 'XOF': 'West African CFA franc',
  'XAF': 'Central African CFA franc', 'DZD': 'Algerian dinar', 'TND': 'Tunisian dinar',
  'AOA': 'Angolan kwanza', 'MZN': 'Mozambican metical', 'BWP': 'Botswana pula',
  'NAD': 'Namibian dollar', 'MWK': 'Malawian kwacha', 'SLE': 'Sierra Leonean leone',
  'LRD': 'Liberian dollar', 'GMD': 'Gambian dalasi', 'GNF': 'Guinean franc',
  'CDF': 'Congolese franc', 'MUR': 'Mauritian rupee',
  'CAD': 'Canadian dollar', 'MXN': 'Mexican peso', 'BRL': 'Brazilian real',
  'ARS': 'Argentine peso', 'CLP': 'Chilean peso', 'COP': 'Colombian peso',
  'PEN': 'Peruvian sol', 'JMD': 'Jamaican dollar', 'TTD': 'Trinidad and Tobago dollar',
  'DOP': 'Dominican peso',
  'CHF': 'Swiss franc', 'NOK': 'Norwegian krone', 'SEK': 'Swedish krona',
  'DKK': 'Danish krone', 'PLN': 'Polish złoty', 'CZK': 'Czech koruna',
  'HUF': 'Hungarian forint', 'RON': 'Romanian leu', 'BGN': 'Bulgarian lev',
  'UAH': 'Ukrainian hryvnia', 'TRY': 'Turkish lira', 'RUB': 'Russian rouble',
  'ISK': 'Icelandic króna', 'RSD': 'Serbian dinar', 'GEL': 'Georgian lari',
  'AED': 'UAE dirham', 'SAR': 'Saudi riyal', 'QAR': 'Qatari riyal',
  'KWD': 'Kuwaiti dinar', 'BHD': 'Bahraini dinar', 'OMR': 'Omani rial',
  'ILS': 'Israeli shekel', 'JOD': 'Jordanian dinar',
  'INR': 'Indian rupee', 'PKR': 'Pakistani rupee', 'BDT': 'Bangladeshi taka',
  'LKR': 'Sri Lankan rupee', 'NPR': 'Nepalese rupee', 'CNY': 'Chinese yuan',
  'HKD': 'Hong Kong dollar', 'TWD': 'New Taiwan dollar', 'JPY': 'Japanese yen',
  'KRW': 'South Korean won', 'SGD': 'Singapore dollar', 'MYR': 'Malaysian ringgit',
  'IDR': 'Indonesian rupiah', 'THB': 'Thai baht', 'VND': 'Vietnamese đồng',
  'PHP': 'Philippine peso', 'KZT': 'Kazakhstani tenge', 'UZS': 'Uzbekistani som',
  'AUD': 'Australian dollar', 'NZD': 'New Zealand dollar', 'FJD': 'Fijian dollar',
};

/// Popular choices listed first; everything else alphabetically after.
const _popular = [
  'NGN', 'USD', 'EUR', 'GBP', 'GHS', 'KES', 'ZAR', 'CAD', 'INR', 'AED',
];

Future<void> showCurrencyPickerSheet(BuildContext context) {
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CurrencyPicker(),
  );
}

String currencyLabel(String code) {
  final name = kCurrencyNames[code];
  return name == null ? code : '$name ($code)';
}

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker();
  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  final _search = TextEditingController();
  String? _saving;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _codes {
    final all = DisplayCurrency.rates.keys.where((c) => c.length == 3).toSet()
      ..add('USD');
    final rest = all.where((c) => !_popular.contains(c)).toList()
      ..sort((a, b) => (kCurrencyNames[a] ?? a).compareTo(kCurrencyNames[b] ?? b));
    final ordered = [..._popular.where(all.contains), ...rest];
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return ordered;
    return ordered
        .where(
          (c) =>
              c.toLowerCase().contains(q) ||
              (kCurrencyNames[c]?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  Future<void> _pick(String code) async {
    if (_saving != null) return;
    setState(() {
      _saving = code;
      _error = null;
    });
    try {
      await ZendScope.read(context).setDisplayCurrency(code);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = null;
          _error = "That didn't save. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final mq = MediaQuery.of(context);
    final codes = _codes;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        height: ((mq.size.height - mq.viewInsets.bottom) * 0.88).clamp(
          320.0,
          mq.size.height,
        ),
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(PhosphorIconsRegular.x, color: zt.textPrimary, size: 22),
                    ),
                    Expanded(
                      child: Text(
                        'Currency',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  'Amounts across Zend show in this currency. Your money '
                  'stays the same; only how it’s shown changes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 18),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: ZendColors.destructive),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: codes.length,
                  separatorBuilder: (_, _) => Divider(color: zt.border, height: 1),
                  itemBuilder: (context, i) {
                    final code = codes[i];
                    final selected = code == DisplayCurrency.code;
                    final example = DisplayCurrency.rates[code] == null
                        ? null
                        : formatCurrency(10 * DisplayCurrency.rates[code]!, code);
                    return InkWell(
                      onTap: () => _pick(code),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                code,
                                style: ZendTextStyles.tabularNumeric.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: zt.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                kCurrencyNames[code] ?? code,
                                style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textPrimary),
                              ),
                            ),
                            if (example != null && !selected)
                              Text(
                                example,
                                style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary),
                              ),
                            if (_saving == code)
                              const ZendLoader(size: 18)
                            else if (selected)
                              Icon(PhosphorIconsBold.check, size: 18, color: zt.accent),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
