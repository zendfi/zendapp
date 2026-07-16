import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/wallet_export_service.dart';
import 'package:solar_icons/solar_icons.dart';

/// Settings > Security > Export encrypted backup
///
/// Flow:
/// 1. PIN confirmation (6-digit)
/// 2. Warning screen ("Store this file safely...")
/// 3. Generate JSON + share via share_plus
class ExportBackupScreen extends StatefulWidget {
  const ExportBackupScreen({super.key});
  @override
  State<ExportBackupScreen> createState() => _ExportBackupScreenState();
}

enum _ExportBackupStage { pin, warning, exporting, done }

class _ExportBackupScreenState extends State<ExportBackupScreen> {
  _ExportBackupStage _stage = _ExportBackupStage.pin;
  String _pinDigits = '';
  String? _errorMessage;
  bool _loading = false;
  late String _verifiedPin;

  void _onPinKey(String value) {
    if (_loading) return;
    setState(() {
      _errorMessage = null;
      if (value == 'del') {
        if (_pinDigits.isNotEmpty) _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        return;
      }
      if (_pinDigits.length >= 6) return;
      _pinDigits += value;
    });
    if (_pinDigits.length == 6) _verifyPin(_pinDigits);
  }

  Future<void> _verifyPin(String pin) async {
    setState(() => _loading = true);
    try {
      final model = ZendScope.of(context);
      await model.walletService.verifyLocalPin(pin);
      if (!mounted) return;
      _verifiedPin = pin;
      setState(() { _loading = false; _stage = _ExportBackupStage.warning; });
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() { _loading = false; _errorMessage = 'Incorrect PIN'; _pinDigits = ''; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMessage = 'Something went wrong'; _pinDigits = ''; });
    }
  }

  Future<void> _export() async {
    setState(() => _stage = _ExportBackupStage.exporting);
    try {
      final model = ZendScope.of(context);
      final service = WalletExportService(model.walletService);
      final json = await service.exportEncryptedBackup(_verifiedPin);
      final filename = WalletExportService.exportFilename();
      if (!mounted) return;
      // Share the JSON as a text file via share_plus
      await Share.share(json, subject: filename);
      if (!mounted) return;
      setState(() => _stage = _ExportBackupStage.done);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _ExportBackupStage.warning);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final compact = MediaQuery.of(context).size.height < 760;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Export backup',
          style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 20, color: zt.textPrimary)),
      ),
      body: SafeArea(
        child: switch (_stage) {
          _ExportBackupStage.pin => _PinStage(
              digits: _pinDigits,
              errorMessage: _errorMessage,
              loading: _loading,
              compact: compact,
              zt: zt,
              onKey: _onPinKey,
            ),
          _ExportBackupStage.warning => _WarningStage(zt: zt, onConfirm: _export),
          _ExportBackupStage.exporting => Center(child: ZendLoader()),
          _ExportBackupStage.done => _DoneStage(zt: zt, onDone: () => Navigator.of(context).pop()),
        },
      ),
    );
  }
}

class _PinStage extends StatelessWidget {
  const _PinStage({required this.digits, this.errorMessage, required this.loading,
      required this.compact, required this.zt, required this.onKey});
  final String digits;
  final String? errorMessage;
  final bool loading, compact;
  final ZendTheme zt;
  final void Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SizedBox(height: compact ? 24 : 40),
          Text('Confirm your PIN', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 26, color: zt.textPrimary)),
          const SizedBox(height: 8),
          Text('Enter your PIN to generate the backup file.', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
          SizedBox(height: compact ? 32 : 48),
          _PinDots(filledCount: digits.length, zt: zt),
          const SizedBox(height: 16),
          SizedBox(
            height: 20,
            child: errorMessage != null
                ? Text(errorMessage!, textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.destructive))
                : loading
                    ? Center(child: ZendLoader(size: 16, strokeWidth: 1.5))
                    : null,
          ),
          const Spacer(),
          Opacity(
            opacity: loading ? 0.3 : 1.0,
            child: IgnorePointer(
              ignoring: loading,
              child: _Keypad(onTap: onKey, keyHeight: compact ? 56 : 64, zt: zt),
            ),
          ),
          SizedBox(height: compact ? 12 : 24),
        ],
      ),
    );
  }
}

class _WarningStage extends StatelessWidget {
  const _WarningStage({required this.zt, required this.onConfirm});
  final ZendTheme zt;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ZendColors.destructive.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZendColors.destructive.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const Icon(SolarIconsBold.infoCircle, color: ZendColors.destructive, size: 40),
                const SizedBox(height: 12),
                Text('Store this file safely.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 22, color: zt.textPrimary)),
                const SizedBox(height: 8),
                Text(
                  'Anyone with this file and your PIN can access your wallet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: zt.accent,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
              ),
              child: const Text('I understand — export backup',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(fontFamily: 'DMSans', color: zt.textSecondary)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DoneStage extends StatelessWidget {
  const _DoneStage({required this.zt, required this.onDone});
  final ZendTheme zt;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: ZendColors.positive, shape: BoxShape.circle),
            child: const Icon(SolarIconsBold.checkCircle, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text('Backup exported',
            style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, color: zt.textPrimary)),
          const SizedBox(height: 8),
          Text('Store it somewhere safe.',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: zt.accent,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
              ),
              child: const Text('Done', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared PIN UI ─────────────────────────────────────────────────────────────

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filledCount, required this.zt});
  final int filledCount;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? zt.accent : Colors.transparent,
              border: Border.all(color: filled ? zt.accent : zt.border, width: 2),
            ),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onTap, required this.keyHeight, required this.zt});
  final void Function(String) onTap;
  final double keyHeight;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    const keys = ['1','2','3','4','5','6','7','8','9','','0','del'];
    return Column(children: [
      for (var row = 0; row < 4; row++) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (var col = 0; col < 3; col++)
            _Key(label: keys[row*3+col], onTap: onTap, height: keyHeight, zt: zt),
          ],
        ),
        if (row < 3) const SizedBox(height: 14),
      ],
    ]);
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap, required this.height, required this.zt});
  final String label;
  final void Function(String) onTap;
  final double height;
  final ZendTheme zt;
  @override State<_Key> createState() => _KeyState();
}
class _KeyState extends State<_Key> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return SizedBox(width: 80, height: widget.height);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) { setState(() => _pressed = true); widget.onTap(widget.label); },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        scale: _pressed ? 0.92 : 1.0,
        child: SizedBox(width: 80, height: widget.height,
          child: Center(
            child: widget.label == 'del'
                ? ZendBackspaceIcon(color: widget.zt.textPrimary, size: 22)
                : Text(widget.label, style: TextStyle(fontFamily: 'DMMono', fontSize: 22,
                    color: widget.zt.textPrimary, fontWeight: FontWeight.w400)),
          ),
        ),
      ),
    );
  }
}
