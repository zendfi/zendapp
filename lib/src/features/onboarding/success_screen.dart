import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../../core/zend_state.dart';
import 'pin_setup_screen.dart';
import 'username_screen.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key, required this.username});

  final String username;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  Future<void> _onGoToZendApp() async {
    final model = ZendScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    model.startLoading('Setting up your account...');

    try {
      final displayName = model.currentDisplayName ?? model.username;
      final zendtag = model.username;
      final registerResponse = await model.authService.register(displayName, zendtag);

      if (!mounted) return;

      model.setAuthenticated(
        userId: registerResponse.userId,
        zendtag: registerResponse.zendtag,
        displayName: displayName,
      );

      await model.walletService.generateKeypair();

      model.stopLoading();
      if (!mounted) return;

      navigator.pushAndRemoveUntil(zendRoute(page: const PinSetupScreen()), (route) => false);
    } on ApiException catch (e) {
      model.stopLoading();
      if (!mounted) return;

      if (e.errorCode == 'PHONE_ALREADY_REGISTERED') {
        messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
        navigator.popUntil((route) => route.isFirst);
      } else if (e.errorCode == 'ZENDTAG_UNAVAILABLE') {
        messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
        navigator.pushReplacement(zendRoute(page: const UsernameScreen()));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } catch (e) {
      model.stopLoading();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: ZendColors.bgSecondary,
                    child: Icon(Icons.person, color: ZendColors.textPrimary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "You're in, @${widget.username}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      height: 1.08,
                      color: ZendColors.textOnDeep,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'zdfi.me/${widget.username}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      color: Color(0x80E8F4EC),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your payment link is live. Share it anywhere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0x99E8F4EC),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: 'Go to ZendApp',
                    backgroundColor: ZendColors.accentBright,
                    foregroundColor: ZendColors.textPrimary,
                    onPressed: _onGoToZendApp,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
