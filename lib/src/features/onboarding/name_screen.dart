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
    final model = ZendScope.of(context);
    final waitlistMatched = model.pendingWaitlistMatch;
    // Pull the first name out of the stored value for the warm
    // greeting. Falls back to a gentler line when no name was given
    // during waitlist signup.
    final waitlistFirstName = (model.pendingWaitlistFullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first;

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
                    const SizedBox(height: 40),
                    if (waitlistMatched) ...[
                      // Quiet eyebrow above the headline. DM Mono small
                      // caps for the chrome label, Instrument Serif
                      // italic for the headline below it. Uses the
                      // existing palette — no new accent introduced.
                      Text(
                        'YOU MADE IT',
                        style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          letterSpacing: 1.8,
                          color: ZendColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        waitlistFirstName.isEmpty
                            ? "Welcome in. Let's set up your account."
                            : "Welcome in, $waitlistFirstName.",
                        style: const TextStyle(
                          fontFamily: 'InstrumentSerif',
                          fontSize: 28,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "We've been holding a spot for you. A couple of details and you're in.",
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          color: ZendColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ] else ...[
                      const Text(
                        "What's your name?",
                        style: TextStyle(
                          fontFamily: 'InstrumentSerif',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    TextField(
                      controller: _firstName,
                      decoration: const InputDecoration(
                        hintText: 'First name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _lastName,
                      decoration: const InputDecoration(
                        hintText: 'Last name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
                      ),
                    ),
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
