import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'customisation_panel.dart';
import 'request_confirmation_screen.dart';
import 'payment_request.dart';
import 'request_utils.dart';

Future<void> showRequestDrawer(
  BuildContext context, {
  double? initialAmount,
  bool amountReadOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: RequestDrawerSheet(
        initialAmount: initialAmount,
        amountReadOnly: amountReadOnly,
      ),
    ),
  );
}

class RequestDrawerSheet extends StatefulWidget {
  const RequestDrawerSheet({
    super.key,
    this.initialAmount,
    this.amountReadOnly = false,
  });

  final double? initialAmount;

  final bool amountReadOnly;

  @override
  State<RequestDrawerSheet> createState() => _RequestDrawerSheetState();
}

class _RequestDrawerSheetState extends State<RequestDrawerSheet> {
  static const int _descriptionMaxLength = 140;

  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;

  double _amount = 0;
  DateTime? _expiryDate;
  RequestCustomisation? _customisation;
  bool _showCustomisation = false;
  String? _expiryError;

  @override
  void initState() {
    super.initState();
    _amount = widget.initialAmount ?? 0;
    _amountController = TextEditingController(
      text: _amount > 0 ? _amount.toString() : '',
    );
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canCreate => _amount > 0;

  String get _titleText {
    if (_amount > 0) {
      return 'Create payment request for ${formatRequestAmount(_amount)}';
    }
    return 'Create payment request';
  }

  void _onAmountChanged(String value) {
    final parsed = validateAmountInput(value);
    setState(() {
      _amount = parsed ?? 0;
    });
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null) {
      if (!isValidExpiryDate(picked)) {
        setState(() {
          _expiryError = 'Please select a future date';
        });
      } else {
        setState(() {
          _expiryDate = picked;
          _expiryError = null;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _onCreateLink() {
    if (!_canCreate) return;

    final model = ZendScope.of(context);
    final requestId = generateRequestId();
    final link = buildRequestLink(model.username, requestId);

    final request = PaymentRequest(
      id: requestId,
      link: link,
      amount: _amount,
      description: _descriptionController.text.trim(),
      createdAt: DateTime.now(),
      expiryDate: _expiryDate,
      customisation: _customisation,
      status: PaymentRequestStatus.pending,
    );

    model.addPaymentRequest(request);

    Navigator.of(context).pop();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushZendSlide(
        context,
        RequestConfirmationScreen(paymentRequest: request),
        rootNavigator: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final descRemaining = remainingCharacters(
      _descriptionController.text,
      _descriptionMaxLength,
    );

    return Container(
      decoration: const BoxDecoration(
        color: ZendColors.bgPrimary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ZendScrollPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ZendSheetHandle(),
              const SizedBox(height: ZendSpacing.lg),

              Text(
                _titleText,
                style: const TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: ZendColors.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xl),

              if (widget.amountReadOnly) ...[
                Text(
                  formatRequestAmount(_amount),
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: ZendColors.textPrimary,
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: _onAmountChanged,
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: ZendColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    prefixText: r'$ ',
                    prefixStyle: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: ZendColors.textSecondary,
                    ),
                    hintText: '0.00',
                    hintStyle: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: ZendColors.textSecondary,
                    ),
                    filled: true,
                    fillColor: ZendColors.bgSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZendRadii.md),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ZendSpacing.md,
                      vertical: ZendSpacing.sm,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: ZendSpacing.lg),

              TextField(
                controller: _descriptionController,
                maxLines: 2,
                minLines: 1,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_descriptionMaxLength),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Description (optional)',
                  hintStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: ZendColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: ZendColors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: ZendColors.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xxs),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$descRemaining remaining',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: descRemaining < 20
                        ? ZendColors.destructive
                        : ZendColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: ZendSpacing.md),

              _TappableRow(
                label: 'Customise payment page',
                trailing: _customisation != null
                    ? const Icon(Icons.check_circle, size: 18, color: ZendColors.accentBright)
                    : const Icon(Icons.chevron_right, size: 18, color: ZendColors.textSecondary),
                onTap: () => setState(() {
                  _showCustomisation = !_showCustomisation;
                }),
              ),
              if (_showCustomisation) ...[
                const SizedBox(height: ZendSpacing.sm),
                CustomisationPanel(
                  initial: _customisation,
                  onConfirm: (value) {
                    setState(() {
                      _customisation = value;
                      _showCustomisation = false;
                    });
                  },
                ),
              ],
              const SizedBox(height: ZendSpacing.sm),

              _TappableRow(
                label: _expiryDate != null
                    ? 'Expires ${_formatDate(_expiryDate!)}'
                    : 'Set expiry date',
                trailing: const Icon(Icons.chevron_right, size: 18, color: ZendColors.textSecondary),
                onTap: _pickExpiryDate,
              ),
              if (_expiryError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(
                  _expiryError!,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
              ],

              // ── Spacer to push button to bottom ──
              const SizedBox(height: ZendSpacing.xxl),
              const Spacer(),

              // ── Create link button ──
              PrimaryButton(
                label: 'Create link',
                onPressed: _canCreate ? _onCreateLink : () {},
                backgroundColor: _canCreate
                    ? ZendColors.accent
                    : ZendColors.bgSecondary,
                foregroundColor: _canCreate
                    ? ZendColors.textOnDeep
                    : ZendColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TappableRow extends StatelessWidget {
  const _TappableRow({
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ZendRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZendSpacing.md,
          vertical: ZendSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: ZendColors.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: ZendColors.textPrimary,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
