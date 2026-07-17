import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';
import 'package:solar_icons/solar_icons.dart';

class DropConfirmStage extends StatefulWidget {
  const DropConfirmStage({
    super.key,
    required this.amount,
    required this.receiver,
    required this.note,
    required this.requiresBiometric, // true for Tier 3
    required this.onConfirm,
    required this.onCancel,
  });

  final double amount;
  final DiscoveredReceiver receiver;
  final String? note;
  final bool requiresBiometric;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  State<DropConfirmStage> createState() => _DropConfirmStageState();
}

class _DropConfirmStageState extends State<DropConfirmStage> {
  int _secondsRemaining = 60;
  Timer? _timer;
  bool _biometricInProgress = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        _timer?.cancel();
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _amountFormatted {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _zendtag => widget.receiver.gattPayload?.zendtag 
      ?? widget.receiver.preview?.zendtag 
      ?? '?';

  Future<void> _onConfirmTapped() async {
    if (widget.requiresBiometric) {
      setState(() => _biometricInProgress = true);
      try {
        final auth = LocalAuthentication();
        final authenticated = await auth.authenticate(
          localizedReason: 'Confirm sending $_amountFormatted to @$_zendtag',
          options: const AuthenticationOptions(biometricOnly: true),
        );
        if (!mounted) return;
        if (authenticated) {
          widget.onConfirm();
        } else {
          setState(() => _biometricInProgress = false);
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => _biometricInProgress = false);
      }
    } else {
      widget.onConfirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final senderAvatarUrl = model.currentAvatarUrl;
    final senderInitial = model.currentZendtag?.isNotEmpty == true
        ? model.currentZendtag![0].toUpperCase()
        : 'Y';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // Sender → receiver avatars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ZendAvatar(radius: 22, photoUrl: senderAvatarUrl, initials: senderInitial),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward, size: 18, color: zt.textSecondary),
              const SizedBox(width: 10),
              ZendAvatar(
                radius: 22,
                photoUrl: widget.receiver.preview?.avatarUrl,
                initials: _zendtag.isNotEmpty ? _zendtag[0].toUpperCase() : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Drop $_amountFormatted',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 32,
              fontStyle: FontStyle.italic,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'to @$_zendtag',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: zt.textSecondary,
            ),
          ),
          if (widget.note != null && widget.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.note!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 12,
                color: zt.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Timeout indicator
          Text(
            'Auto-cancels in ${_secondsRemaining}s',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 11,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // Confirm button
          GestureDetector(
            onTap: _biometricInProgress ? null : _onConfirmTapped,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: zt.accentBright,
                borderRadius: BorderRadius.circular(ZendRadii.pill),
              ),
              alignment: Alignment.center,
              child: _biometricInProgress
                  ? ZendLoader(
                      size: 20,
                      strokeWidth: 2,
                      color: Colors.white,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.requiresBiometric) ...[
                          const Icon(SolarIconsBold.faceScanCircle, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          widget.requiresBiometric ? 'Confirm with Biometric' : 'Confirm Drop',
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onCancel,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Cancel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
