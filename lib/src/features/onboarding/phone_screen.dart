import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _controller = TextEditingController();
  String _countryCode = _countryOptions.first.dialCode;

  Future<void> _pickCountryCode() async {
    final selected = await showModalBottomSheet<_CountryOption>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            itemCount: _countryOptions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = _countryOptions[index];
              return ListTile(
                title: Text(option.name, style: const TextStyle(fontFamily: 'DMSans')),
                subtitle: Text(option.isoCode, style: const TextStyle(color: ZendColors.textSecondary)),
                trailing: Text(option.dialCode, style: const TextStyle(fontFamily: 'DMMono')),
                onTap: () => Navigator.of(context).pop(option),
              );
            },
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    setState(() => _countryCode = selected.dialCode);
  }

  Future<void> _onContinue() async {
    final rawNumber = _controller.text.trim();
    if (rawNumber.isEmpty) return;

    final digitsOnly = rawNumber.replaceAll(RegExp(r'\D'), '');
    final normalized = digitsOnly.startsWith('0') ? digitsOnly.substring(1) : digitsOnly;
    if (normalized.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number.')),
      );
      return;
    }

    final phoneNumber = '$_countryCode$normalized';

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
    } on ZendException catch (e) {
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
                        _CountryPill(code: _countryCode, onTap: _pickCountryCode),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
  const _CountryPill({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZendRadii.pill),
      child: Container(
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
      ),
    );
  }
}

class _CountryOption {
  const _CountryOption(this.name, this.dialCode, this.isoCode);

  final String name;
  final String dialCode;
  final String isoCode;
}

const List<_CountryOption> _countryOptions = [
  _CountryOption('Nigeria', '+234', 'NG'),
  _CountryOption('United States', '+1', 'US'),
  _CountryOption('United Kingdom', '+44', 'GB'),
  _CountryOption('Ghana', '+233', 'GH'),
  _CountryOption('Kenya', '+254', 'KE'),
  _CountryOption('South Africa', '+27', 'ZA'),
  _CountryOption('India', '+91', 'IN'),
  _CountryOption('Canada', '+1', 'CA'),
  _CountryOption('France', '+33', 'FR'),
  _CountryOption('Germany', '+49', 'DE'),
];
