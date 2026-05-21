import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/sse_service.dart';
import '../../services/sound_service.dart';

class ShowQrScreen extends StatefulWidget {
  const ShowQrScreen({
    super.key,
    required this.username,
    required this.amountUsdc,
    required this.note,
  });

  final String username;
  final double amountUsdc;
  final String? note;

  @override
  State<ShowQrScreen> createState() => _ShowQrScreenState();
}

const Duration _qrLifetime = Duration(minutes: 5);

enum _ShowQrState { generating, showing, received, error }

class _ShowQrScreenState extends State<ShowQrScreen> {
  _ShowQrState _state = _ShowQrState.generating;

  String? _qrUrl;

  int _secondsLeft = _qrLifetime.inSeconds;

  Timer? _countdownTimer;
  StreamSubscription<SseEvent>? _sseSub;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _subscribeToSse();
    _generateRequest();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sseSub?.cancel();
    super.dispose();
  }


  void _subscribeToSse() {
    final model = ZendScope.of(context);
    _sseSub = model.sseService.events.listen((event) {
      if (!mounted) return;
      if (event.type != SseEventType.transferUpdate) return;

      final direction = event.data['direction'] as String?;
      if (direction != 'received') return;

      final amountStr = event.data['amount_usdc'] as String?;
      final receivedAmount = amountStr != null ? double.tryParse(amountStr) : null;
      if (receivedAmount == null) return;

      if ((receivedAmount - widget.amountUsdc).abs() > 0.005) return;

      _onPaymentReceived();
    });
  }

  Future<void> _generateRequest() async {
    setState(() => _state = _ShowQrState.generating);
    _countdownTimer?.cancel();

    try {
      final model = ZendScope.of(context);
      final response = await model.walletService.apiClient.createPaymentRequest(
        amountUsdc: widget.amountUsdc,
        description: widget.note,
        expiresAt: DateTime.now().add(_qrLifetime),
      );

      if (!mounted) return;

      final requestLinkId = response['request_link_id'] as String?;
      if (requestLinkId == null) throw Exception('No request_link_id in response');

      final url = 'https://zdfi.me/@${widget.username}/$requestLinkId';

      setState(() {
        _qrUrl = url;
        _secondsLeft = _qrLifetime.inSeconds;
        _state = _ShowQrState.showing;
        _errorMessage = null;
      });

      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not generate QR. Check your connection.';
        _state = _ShowQrState.error;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _generateRequest();
      }
    });
  }

  void _onPaymentReceived() {
    _countdownTimer?.cancel();
    _sseSub?.cancel();
    HapticFeedback.mediumImpact();
    unawaited(SoundService.playZentSuccess());
    setState(() => _state = _ShowQrState.received);
    ZendScope.of(context).fetchBalance();
    ZendScope.of(context).fetchHistory();
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ShowQrState.generating:
        return _GeneratingView(key: const ValueKey('generating'));

      case _ShowQrState.showing:
        return _ShowingView(
          key: ValueKey('showing-$_qrUrl'),
          qrUrl: _qrUrl!,
          amountFormatted: _formatAmount(widget.amountUsdc),
          note: widget.note,
          secondsLeft: _secondsLeft,
          totalSeconds: _qrLifetime.inSeconds,
          onDismiss: () => Navigator.of(context).pop(),
        );

      case _ShowQrState.received:
        return _ReceivedView(
          key: const ValueKey('received'),
          amountFormatted: _formatAmount(widget.amountUsdc),
          note: widget.note,
          onDone: () => Navigator.of(context).pop(),
        );

      case _ShowQrState.error:
        return _ErrorView(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: _generateRequest,
          onDismiss: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _GeneratingView extends StatelessWidget {
  const _GeneratingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ZendColors.accentPop,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Getting ready…',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: Color(0x99E8F4EC),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShowingView extends StatelessWidget {
  const _ShowingView({
    super.key,
    required this.qrUrl,
    required this.amountFormatted,
    required this.note,
    required this.secondsLeft,
    required this.totalSeconds,
    required this.onDismiss,
  });

  final String qrUrl;
  final String amountFormatted;
  final String? note;
  final int secondsLeft;
  final int totalSeconds;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft / totalSeconds;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Color(0x99E8F4EC)),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),

        const Spacer(),

        Text(
          amountFormatted,
          style: const TextStyle(
            fontFamily: 'InstrumentSerif',
            fontStyle: FontStyle.italic,
            fontSize: 52,
            color: ZendColors.textOnDeep,
            height: 1.0,
          ),
        ),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note!,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: Color(0x99E8F4EC),
            ),
          ),
        ],
        const SizedBox(height: 28),

        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 260,
              height: 260,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                backgroundColor: const Color(0x1AE8F4EC),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0x4052B788), // muted accent green
                ),
              ),
            ),
            Container(
              width: 228,
              height: 228,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: qrUrl,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        const Text(
          'Ask them to scan this',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 14,
            color: Color(0x66E8F4EC),
          ),
        ),

        const Spacer(),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ReceivedView extends StatefulWidget {
  const _ReceivedView({
    super.key,
    required this.amountFormatted,
    required this.note,
    required this.onDone,
  });

  final String amountFormatted;
  final String? note;
  final VoidCallback onDone;

  @override
  State<_ReceivedView> createState() => _ReceivedViewState();
}

class _ReceivedViewState extends State<_ReceivedView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: ZendColors.positive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Received!',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 44,
                color: ZendColors.textOnDeep,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.amountFormatted,
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 20,
                color: Color(0x99E8F4EC),
              ),
            ),
            if (widget.note != null && widget.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.note!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: Color(0x66E8F4EC),
                ),
              ),
            ],
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: GestureDetector(
                onTap: widget.onDone,
                child: Container(
                  decoration: BoxDecoration(
                    color: ZendColors.accent,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ZendColors.textOnDeep,
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: Color(0x44E8F4EC),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: Color(0x99E8F4EC),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  decoration: BoxDecoration(
                    color: ZendColors.accent,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Try again',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ZendColors.textOnDeep,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onDismiss,
              child: const Text(
                'Go back',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: Color(0x66E8F4EC),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
