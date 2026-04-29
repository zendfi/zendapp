import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'send_success_screen.dart';
import 'send_error_screen.dart';

class SendNoteScreen extends StatefulWidget {
  const SendNoteScreen({
    super.key,
    required this.recipientName,
    required this.handle,
    required this.amount,
    this.external = false,
  });

  final String recipientName;
  final String handle;
  final num amount;
  final bool external;

  @override
  State<SendNoteScreen> createState() => _SendNoteScreenState();
}

class _SendNoteScreenState extends State<SendNoteScreen> {
  final _noteController = TextEditingController();
  final _noteFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noteFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);

    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        color: ZendColors.textOnDeep,
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '\$${widget.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 30,
                      color: ZendColors.textOnDeep,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.86,
                decoration: const BoxDecoration(
                  color: ZendColors.bgPrimary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ZendScrollPage(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Pay \$${widget.amount.toStringAsFixed(0)} to ',
                                style: const TextStyle(
                                  fontFamily: 'InstrumentSerif',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: CircleAvatar(
                                    radius: 11,
                                    backgroundColor: ZendColors.bgSecondary,
                                    child: Text(
                                      widget.recipientName.isNotEmpty ? widget.recipientName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 11, color: ZendColors.textPrimary),
                                    ),
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: '${widget.recipientName} for ',
                                style: const TextStyle(
                                  fontFamily: 'InstrumentSerif',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _noteController,
                          focusNode: _noteFocusNode,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: "What's it for?",
                            filled: false,
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(fontSize: 18, color: ZendColors.textPrimary),
                        ),
                        const SizedBox(height: 18),
                        if (widget.external) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: ZendColors.bgSecondary,
                              borderRadius: BorderRadius.circular(ZendRadii.md),
                            ),
                            child: const Column(
                              children: [
                                _QuoteRow(label: 'Sending', value: r'\$65.00'),
                                SizedBox(height: 10),
                                _QuoteRow(label: 'Fee', value: r'\$0.99'),
                                SizedBox(height: 10),
                                Divider(color: ZendColors.border),
                                SizedBox(height: 10),
                                _QuoteRow(label: 'Carissa receives', value: '₦94,241'),
                                SizedBox(height: 10),
                                _QuoteRow(label: 'Arrives', value: '~2 hours (GTBank)'),
                                SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '1 USD = 1,542.50 NGN · Rate locked for 15 min',
                                    style: TextStyle(fontSize: 11, color: ZendColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (_noteController.text.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {},
                              child: const Text(
                                'Continue →',
                                style: TextStyle(color: ZendColors.accent),
                              ),
                            ),
                          ),
                        const Spacer(),
                        PrimaryButton(
                          label: 'Send \$${widget.amount.toStringAsFixed(0)}',
                          onPressed: () async {
                            await HapticFeedback.mediumImpact();
                            if (!context.mounted) return;
                            try {
                              model.startLoading('Processing transfer...');
                              await Future.delayed(const Duration(milliseconds: 1500));
                              
                              model.sendMoney(
                                name: widget.recipientName,
                                note: _noteController.text.trim().isEmpty ? 'Sent from ZendApp' : _noteController.text.trim(),
                                amount: widget.amount.toDouble(),
                                external: widget.external,
                              );
                              if (!context.mounted) return;
                              model.stopLoading();
                              
                              if (!context.mounted) return;
                              pushAndRemoveUntilZendSlide(
                                context,
                                SendSuccessScreen(
                                  recipientName: widget.recipientName,
                                  amount: widget.amount.toDouble(),
                                ),
                                rootNavigator: true,
                              );
                            } catch (e) {
                              model.stopLoading();
                              if (!context.mounted) return;
                              pushZendSlide(
                                context,
                                SendErrorScreen(
                                  errorMessage: 'Payment failed. Please try again.',
                                  onRetry: () {},
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13,
            color: ZendColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
