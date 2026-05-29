import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'username_screen.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Prefill name fields from the waitlist hold-over (set by the OTP
    // screen on the new-user path when the email matched a Zend!
    // consumer-waitlist row). Splits the stored full name on the first
    // whitespace; everything after becomes the last-name field. The
    // user can edit either field freely.
    //
    // Done in initState (not didChangeDependencies) because the
    // ZendState reference is stable for the lifetime of the screen.
    final model = ZendScope.of(context);
    final stored = model.pendingWaitlistFullName?.trim() ?? '';
    if (stored.isNotEmpty) {
      final parts = stored.split(RegExp(r'\s+'));
      _firstName.text = parts.first;
      if (parts.length > 1) {
        _lastName.text = parts.sublist(1).join(' ');
      }
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _onContinue() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final displayName = [first, last].where((part) => part.isNotEmpty).join(' ');

    final model = ZendScope.of(context);
    model.setDisplayName(displayName);

    pushZendSlide(context, const UsernameScreen());
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final waitlistMatched = model.pendingWaitlistMatch;
    final waitlistFirstName = (model.pendingWaitlistFullName ?? '').trim().split(RegExp(r'\s+')).first;

    return Scaffold(
      backgroundColor: zt.bgPrimary,
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
                    const SizedBox(height: 40),
                    if (waitlistMatched) ...[
                      Text('YOU MADE IT', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, letterSpacing: 1.8, color: zt.textSecondary)),
                      const SizedBox(height: 8),
                      Text(
                        waitlistFirstName.isEmpty ? "Welcome in. Let's set up your account." : "Welcome in, $waitlistFirstName.",
                        style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, fontStyle: FontStyle.italic, fontWeight: FontWeight.w400, color: zt.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "We've been holding a spot for you. A couple of details and you're in.",
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 32),
                    ] else ...[
                      Text("What's your name?", style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, fontWeight: FontWeight.w700, color: zt.textPrimary)),
                      const SizedBox(height: 24),
                    ],
                    TextField(
                      controller: _firstName,
                      decoration: InputDecoration(
                        hintText: 'First name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: zt.border)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: zt.border)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide.none),
                        hintStyle: TextStyle(color: zt.textSecondary),
                      ),
                      style: TextStyle(color: zt.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _lastName,
                      decoration: InputDecoration(
                        hintText: 'Last name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: zt.border)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: zt.border)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide.none),
                        hintStyle: TextStyle(color: zt.textSecondary),
                      ),
                      style: TextStyle(color: zt.textPrimary),
                    ),
                    const Spacer(),
                    PrimaryButton(label: 'Continue', onPressed: _onContinue),
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
