import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import 'otp_screen.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _controller = TextEditingController(text: '2025550142');
  static const _countryCode = '+44';

  Future<void> _onContinue() async {
    final rawNumber = _controller.text.trim();
    if (rawNumber.isEmpty) return;

    final digits = rawNumber.startsWith('0') ? rawNumber.substring(1) : rawNumber;
    final phoneNumber = '$_countryCode$digits';

    final model = ZendScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    model.startLoading('Sending code...');

    try {
      await model.authService.requestOtp(phoneNumber);
      model.stopLoading();
      if (!mounted) return;
      navigator.push(zendRoute(page: const OtpScreen()));
    } on ApiException catch (e) {
      model.stopLoading();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (e) {
      model.stopLoading();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ZendScrollPage(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 48),
                    Text(
                      "What's your number?",
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 32,
                        height: 1.08,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const _CountryPill(code: _countryCode),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 24,
                              color: ZendColors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0000 000 000',
                              filled: false,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintStyle: TextStyle(color: ZendColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: ZendColors.border),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Continue',
                      onPressed: _onContinue,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryPill extends StatelessWidget {
  const _CountryPill({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ZendColors.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.pill),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: ZendColors.bgDeep,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('◉', style: TextStyle(fontSize: 10, color: ZendColors.accentBright)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            code,
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}
