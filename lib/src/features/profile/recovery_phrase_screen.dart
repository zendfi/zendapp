import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/wallet_export_service.dart';

/// Settings > Security > View recovery phrase
///
/// Flow:
/// 1. PIN confirmation (6-digit)
/// 2. Checkbox confirmation ("I understand this phrase gives full access")
/// 3. Display 12-word mnemonic grid with persistent warning
class RecoveryPhraseScreen extends StatefulWidget {
  const RecoveryPhraseScreen({super.key});
  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

enum _PhraseStage { pin, confirm, display }

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  _PhraseStage _stage = _PhraseStage.pin;
  String _pinDigits = '';
  String? _errorMessage;
  bool _loading = false;
  bool _confirmed = false;
  List<String> _words = [];
  late String _verifiedPin;

  @override
  void dispose() {
    // Zero the words list when leaving
    _words = List.filled(_words.length, '');
    super.dispose();
  }

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
      setState(() { _loading = false; _stage = _PhraseStage.confirm; });
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() { _loading = false; _errorMessage = 'Incorrect PIN'; _pinDigits = ''; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMessage = 'Something went wrong'; _pinDigits = ''; });
    }
  }

  Future<void> _revealMnemonic() async {
    setState(() => _loading = true);
    try {
      final model = ZendScope.of(context);
      final service = WalletExportService(model.walletService);
      final words = await service.exportMnemonic(_verifiedPin);
      if (!mounted) return;
      setState(() { _words = words; _loading = false; _stage = _PhraseStage.display; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to derive recovery phrase. Please try again.')),
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
          icon: Icon(Icons.arrow_back, color: zt.textPrimary),
          onPressed: () {
            // Zero words before popping
            setState(() => _words = List.filled(_words.length, ''));
            Navigator.of(context).pop();
          },
        ),
        title: Text('Recovery phrase',
          style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 20, color: zt.textPrimary)),
      ),
      body: SafeArea(
        child: switch (_stage) {
          _PhraseStage.pin => _PinStage(
              digits: _pinDigits, errorMessage: _errorMessage,
              loading: _loading, compact: compact, zt: zt, onKey: _onPinKey),
          _PhraseStage.confirm => _ConfirmStage(
              confirmed: _confirmed, loading: _loading, zt: zt,
              onToggle: (v) => setState(() => _confirmed = v),
              onReveal: _confirmed ? _revealMnemonic : null),
          _PhraseStage.display => _DisplayStage(words: _words, zt: zt),
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
      child: Column(children: [
        SizedBox(height: compact ? 24 : 40),
        Text('Confirm your PIN', textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 26, color: zt.textPrimary)),
        const SizedBox(height: 8),
        Text('Enter your PIN to view your recovery phrase.', textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
        SizedBox(height: compact ? 32 : 48),
        _PinDots(filledCount: digits.length, zt: zt),
        const SizedBox(height: 16),
        SizedBox(height: 20,
          child: errorMessage != null
              ? Text(errorMessage!, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.destructive))
              : loading
                  ? Center(child: ZendLoader(size: 16, strokeWidth: 1.5))
                  : null),
        const Spacer(),
        Opacity(opacity: loading ? 0.3 : 1.0,
          child: IgnorePointer(ignoring: loading,
            child: _Keypad(onTap: onKey, keyHeight: compact ? 56 : 64, zt: zt))),
        SizedBox(height: compact ? 12 : 24),
      ]),
    );
  }
}

class _ConfirmStage extends StatelessWidget {
  const _ConfirmStage({required this.confirmed, required this.loading,
      required this.zt, required this.onToggle, required this.onReveal});
  final bool confirmed, loading;
  final ZendTheme zt;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ZendColors.destructive.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ZendColors.destructive.withValues(alpha: 0.18)),
          ),
          child: Column(children: [
            const Icon(Icons.key_rounded, color: ZendColors.destructive, size: 36),
            const SizedBox(height: 12),
            Text('Never share this phrase.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 22, color: zt.textPrimary)),
            const SizedBox(height: 8),
            Text('Zend! staff will never ask for it. Anyone with this phrase controls your wallet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
          ]),
        ),
        const SizedBox(height: 24),
        InkWell(
          onTap: () => onToggle(!confirmed),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Checkbox(
                value: confirmed,
                onChanged: (v) => onToggle(v ?? false),
                activeColor: zt.accent,
              ),
              Expanded(child: Text(
                'I understand this phrase gives full access to my wallet',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
              )),
            ]),
          ),
        ),
        const Spacer(),
        SizedBox(width: double.infinity,
          child: FilledButton(
            onPressed: onReveal,
            style: FilledButton.styleFrom(
              backgroundColor: confirmed ? zt.accent : zt.border,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
            ),
            child: loading
                ? ZendLoader(size: 20, strokeWidth: 2, color: Colors.white)
                : const Text('Show recovery phrase',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _DisplayStage extends StatelessWidget {
  const _DisplayStage({required this.words, required this.zt});
  final List<String> words;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Persistent warning banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ZendColors.destructive.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ZendColors.destructive.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: ZendColors.destructive, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Never share this phrase. Zend! staff will never ask for it.',
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: ZendColors.destructive),
            )),
          ]),
        ),
        const SizedBox(height: 24),
        // 12-word grid (3 columns × 4 rows)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: words.length,
          itemBuilder: (context, i) => Container(
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: zt.border),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Text('${i + 1}',
                style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: zt.textSecondary)),
              const SizedBox(width: 4),
              Expanded(child: Text(words[i],
                style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                    fontWeight: FontWeight.w600, color: zt.textPrimary),
                overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Text('Keep this phrase offline and never share it with anyone.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
          ),
          child: const Text('Done', style: TextStyle(fontFamily: 'DMSans', fontSize: 15)),
        ),
        const SizedBox(height: 24),
      ]),
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
    return Row(mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final f = i < filledCount;
        return Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(duration: const Duration(milliseconds: 100),
            width: 16, height: 16,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: f ? zt.accent : Colors.transparent,
              border: Border.all(color: f ? zt.accent : zt.border, width: 2))));
      }));
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
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (var col = 0; col < 3; col++)
            _Key(label: keys[row*3+col], onTap: onTap, height: keyHeight, zt: zt)]),
        if (row < 3) const SizedBox(height: 14),
      ],
    ]);
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap, required this.height, required this.zt});
  final String label; final void Function(String) onTap; final double height; final ZendTheme zt;
  @override State<_Key> createState() => _KeyState();
}
class _KeyState extends State<_Key> {
  bool _p = false;
  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return SizedBox(width: 80, height: widget.height);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) { setState(() => _p = true); widget.onTap(widget.label); },
      onTapCancel: () => setState(() => _p = false),
      onTapUp: (_) => setState(() => _p = false),
      child: AnimatedScale(duration: const Duration(milliseconds: 70), scale: _p ? 0.92 : 1.0,
        child: SizedBox(width: 80, height: widget.height, child: Center(
          child: widget.label == 'del'
              ? ZendBackspaceIcon(color: widget.zt.textPrimary, size: 22)
              : Text(widget.label, style: TextStyle(fontFamily: 'DMMono', fontSize: 22,
                  color: widget.zt.textPrimary, fontWeight: FontWeight.w400))))));
  }
}
