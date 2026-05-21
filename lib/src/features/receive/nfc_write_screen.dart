import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../design/zend_tokens.dart';

/// Full-screen NFC tag writer.
///
/// Writes the user's `zdfi.me/@username` payment URL to a blank (or
/// overwritable) NFC tag. The user holds their phone to the tag while
/// this screen is active.
///
/// Usage:
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => NfcWriteScreen(paymentUrl: 'https://zdfi.me/@alice'),
///   ));
class NfcWriteScreen extends StatefulWidget {
  const NfcWriteScreen({super.key, required this.paymentUrl});

  /// The URL to write — e.g. `https://zdfi.me/@coffeeshop`
  final String paymentUrl;

  @override
  State<NfcWriteScreen> createState() => _NfcWriteScreenState();
}

enum _WriteState { checking, waiting, writing, success, error, unavailable }

class _NfcWriteScreenState extends State<NfcWriteScreen>
    with SingleTickerProviderStateMixin {
  _WriteState _state = _WriteState.checking;
  String? _errorMessage;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkAndStart();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    // Always stop the NFC session when leaving the screen.
    NfcManager.instance.stopSession().catchError((_) {});
    super.dispose();
  }

  Future<void> _checkAndStart() async {
    final available = await NfcManager.instance.isAvailable();
    if (!mounted) return;

    if (!available) {
      setState(() => _state = _WriteState.unavailable);
      return;
    }

    setState(() => _state = _WriteState.waiting);
    _startSession();
  }

  void _startSession() {
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        if (!mounted) return;
        setState(() => _state = _WriteState.writing);

        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw Exception('This tag does not support NDEF.');
          }
          if (!ndef.isWritable) {
            throw Exception('This tag is read-only and cannot be written.');
          }

          // Build a URI record — the most compact NDEF format for a URL.
          // NdefRecord.createUri handles the https:// prefix abbreviation
          // automatically (type 0x04), keeping the tag payload small.
          final record = NdefRecord.createUri(Uri.parse(widget.paymentUrl));
          final message = NdefMessage([record]);

          await ndef.write(message);

          if (!mounted) return;
          setState(() => _state = _WriteState.success);
          await NfcManager.instance.stopSession();
        } catch (e) {
          if (!mounted) return;
          await NfcManager.instance.stopSession(errorMessage: e.toString());
          setState(() {
            _state = _WriteState.error;
            _errorMessage = _friendlyError(e.toString());
          });
        }
      },
    );
  }

  String _friendlyError(String raw) {
    if (raw.contains('read-only')) return 'This tag is read-only.';
    if (raw.contains('NDEF')) return 'This tag doesn\'t support NDEF format.';
    if (raw.contains('capacity') || raw.contains('too small')) {
      return 'Tag storage is too small for this URL.';
    }
    return 'Write failed. Try a different tag.';
  }

  void _retry() {
    setState(() {
      _state = _WriteState.waiting;
      _errorMessage = null;
    });
    _startSession();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ZendColors.textOnDeep),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Write NFC tag',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ZendColors.textOnDeep,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIcon(),
              const SizedBox(height: 32),
              _buildTitle(),
              const SizedBox(height: 12),
              _buildSubtitle(),
              const SizedBox(height: 40),
              _buildAction(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (_state) {
      case _WriteState.checking:
        return const Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ZendColors.accentPop,
            ),
          ),
        );

      case _WriteState.waiting:
        return Center(
          child: ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ZendColors.accent.withValues(alpha: 0.15),
                border: Border.all(
                  color: ZendColors.accentPop.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.nfc_rounded,
                size: 56,
                color: ZendColors.accentPop,
              ),
            ),
          ),
        );

      case _WriteState.writing:
        return const Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: ZendColors.accentPop,
            ),
          ),
        );

      case _WriteState.success:
        return Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ZendColors.positive,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 52,
              color: Colors.white,
            ),
          ),
        );

      case _WriteState.error:
        return Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZendColors.destructive.withValues(alpha: 0.15),
              border: Border.all(color: ZendColors.destructive, width: 2),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 52,
              color: ZendColors.destructive,
            ),
          ),
        );

      case _WriteState.unavailable:
        return const Center(
          child: Icon(
            Icons.nfc_rounded,
            size: 80,
            color: Color(0x44E8F4EC),
          ),
        );
    }
  }

  Widget _buildTitle() {
    final text = switch (_state) {
      _WriteState.checking => 'Checking NFC…',
      _WriteState.waiting => 'Hold tag to phone',
      _WriteState.writing => 'Writing…',
      _WriteState.success => 'Tag written!',
      _WriteState.error => 'Write failed',
      _WriteState.unavailable => 'NFC not available',
    };

    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'InstrumentSerif',
        fontSize: 28,
        fontStyle: FontStyle.italic,
        color: ZendColors.textOnDeep,
      ),
    );
  }

  Widget _buildSubtitle() {
    final text = switch (_state) {
      _WriteState.checking => 'Checking if NFC is supported on this device.',
      _WriteState.waiting =>
        'Place an NFC sticker or tag against the back of your phone.\n\n'
            'Your payment link will be written to it — anyone who taps the tag '
            'will be taken directly to your Zend! payment page.',
      _WriteState.writing => 'Writing your payment link to the tag…',
      _WriteState.success =>
        'Your payment link has been written to the tag.\n\n'
            'Anyone who taps it with their phone will be taken to your Zend! '
            'payment page instantly — no camera needed.',
      _WriteState.error => _errorMessage ?? 'Something went wrong.',
      _WriteState.unavailable =>
        'This device doesn\'t support NFC, or NFC is turned off.\n\n'
            'Check your device settings to enable NFC.',
    };

    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 15,
        color: Color(0x99E8F4EC),
        height: 1.5,
      ),
    );
  }

  Widget _buildAction() {
    switch (_state) {
      case _WriteState.success:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionButton(
              label: 'Write another tag',
              onTap: _retry,
              primary: false,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Done',
              onTap: () => Navigator.of(context).pop(),
              primary: true,
            ),
          ],
        );

      case _WriteState.error:
        return _ActionButton(
          label: 'Try again',
          onTap: _retry,
          primary: true,
        );

      case _WriteState.unavailable:
        return _ActionButton(
          label: 'Go back',
          onTap: () => Navigator.of(context).pop(),
          primary: false,
        );

      default:
        // waiting / checking / writing — no action button needed
        return const SizedBox.shrink();
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: primary
              ? ZendColors.accent
              : const Color(0x1AE8F4EC),
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          border: primary
              ? null
              : Border.all(color: const Color(0x26E8F4EC)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: primary
                ? ZendColors.textOnDeep
                : const Color(0xCCE8F4EC),
          ),
        ),
      ),
    );
  }
}
