import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import 'vibe_sticker_catalog.dart';
import 'package:solar_icons/solar_icons.dart';

class VibeSendResult {
  const VibeSendResult({
    required this.stickerId,
    required this.stickerEmoji,
    required this.stickerLabel,
    required this.amountUsdc,
  });
  final String stickerId;
  final String stickerEmoji;
  final String stickerLabel;
  final double amountUsdc;
}

Future<VibeSendResult?> showVibePickerSheet(
  BuildContext context, {
  required String roomId,
}) {
  return showModalBottomSheet<VibeSendResult>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _VibePickerSheet(roomId: roomId),
  );
}

// ── Step enum ────────────────────────────────────────────────────────────────

enum _VibeStep { amount, sticker, preview }

// ── Main sheet ───────────────────────────────────────────────────────────────

class _VibePickerSheet extends StatefulWidget {
  const _VibePickerSheet({required this.roomId});
  final String roomId;

  @override
  State<_VibePickerSheet> createState() => _VibePickerSheetState();
}

class _VibePickerSheetState extends State<_VibePickerSheet>
    with SingleTickerProviderStateMixin {
  _VibeStep _step = _VibeStep.amount;
  double _amount = 1.0;
  bool _customMode = false;
  final TextEditingController _customCtrl = TextEditingController();
  String? _amountError;

  List<VibeSticker> _stickers = [];
  bool _loadingStickers = true;
  VibeSticker? _selectedSticker;

  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _slideAnim = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _loadStickers();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStickers() async {
    final catalog = VibeStickerCatalog.instance;
    final stickers = await catalog.getStickers(ZendScope.of(context));
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _loadingStickers = false;
        if (stickers.isNotEmpty) _selectedSticker = stickers.first;
      });
    }
  }

  void _goToStep(_VibeStep next) {
    setState(() => _step = next);
    _slideCtrl.forward(from: 0);
  }

  void _increment() {
    HapticFeedback.selectionClick();
    setState(() {
      _amountError = null;
      _amount = (_amount + 1.0).clamp(0.01, 5.0);
    });
  }

  void _decrement() {
    HapticFeedback.selectionClick();
    setState(() {
      _amountError = null;
      _amount = (_amount - 1.0).clamp(0.01, 5.0);
    });
  }

  void _confirmAmount() {
    if (_customMode) {
      final parsed = double.tryParse(_customCtrl.text.trim());
      if (parsed == null || parsed < 0.01) {
        setState(() => _amountError = 'Enter a valid amount');
        return;
      }
      if (parsed > 5.0) {
        setState(() => _amountError = 'Maximum is \$5.00');
        return;
      }
      _amount = parsed;
    }
    _goToStep(_VibeStep.sticker);
  }

  void _confirmSticker() {
    if (_selectedSticker == null) return;
    _goToStep(_VibeStep.preview);
  }

  void _send() {
    if (_selectedSticker == null) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(VibeSendResult(
      stickerId: _selectedSticker!.id,
      stickerEmoji: _selectedSticker!.emoji,
      stickerLabel: _selectedSticker!.label,
      amountUsdc: _amount,
    ));
  }

  // ── UI helpers ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + (bottomInset > 0 ? 0 : bottomPad)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Handle + step header ──
          Column(
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: zt.border,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  if (_step != _VibeStep.amount)
                    GestureDetector(
                      onTap: () => _goToStep(_VibeStep.values[_step.index - 1]),
                      child: Icon(SolarIconsBold.altArrowLeft, color: zt.textSecondary, size: 20),
                    ),
                  if (_step != _VibeStep.amount) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (_step) {
                        _VibeStep.amount => '✨ Send a Vibe',
                        _VibeStep.sticker => 'Pick a sticker',
                        _VibeStep.preview => 'Ready to send',
                      },
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  // Step indicators
                  Row(
                    children: List.generate(3, (i) => Container(
                      width: i == _step.index ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: i == _step.index
                            ? zt.accent
                            : zt.border,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                    )),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Step content ──
          SlideTransition(
            position: _step.index > 0 ? _slideAnim : const AlwaysStoppedAnimation(Offset.zero),
            child: switch (_step) {
              _VibeStep.amount => _AmountStep(
                  zt: zt,
                  amount: _amount,
                  customMode: _customMode,
                  customCtrl: _customCtrl,
                  amountError: _amountError,
                  onIncrement: _increment,
                  onDecrement: _decrement,
                  onToggleCustom: () => setState(() {
                    _customMode = !_customMode;
                    _amountError = null;
                  }),
                  onConfirm: _confirmAmount,
                ),
              _VibeStep.sticker => _StickerStep(
                  zt: zt,
                  stickers: _stickers,
                  loading: _loadingStickers,
                  selected: _selectedSticker,
                  onSelect: (s) => setState(() => _selectedSticker = s),
                  onConfirm: _confirmSticker,
                ),
              _VibeStep.preview => _PreviewStep(
                  zt: zt,
                  amount: _amount,
                  sticker: _selectedSticker,
                  onSend: _send,
                ),
            },
          ),
        ],
      ),
    );
  }
}

// ── Step 1: Amount ────────────────────────────────────────────────────────────

class _AmountStep extends StatelessWidget {
  const _AmountStep({
    required this.zt,
    required this.amount,
    required this.customMode,
    required this.customCtrl,
    required this.amountError,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleCustom,
    required this.onConfirm,
  });

  final ZendTheme zt;
  final double amount;
  final bool customMode;
  final TextEditingController customCtrl;
  final String? amountError;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleCustom;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stepper row
        if (!customMode) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Decrement
              GestureDetector(
                onTap: onDecrement,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: zt.bgPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: zt.border),
                  ),
                  child: Icon(SolarIconsBold.minusCircle, size: 22, color: zt.textSecondary),
                ),
              ),
              const SizedBox(width: 24),
              // Amount display
              Text(
                '\$${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 52,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 24),
              // Increment
              GestureDetector(
                onTap: onIncrement,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: zt.bgPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: zt.border),
                  ),
                  child: Icon(SolarIconsBold.addCircle, size: 22, color: zt.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '\$0.01 – \$5.00 · amount is hidden from recipient until revealed',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: zt.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ] else ...[
          // Custom amount input
          Container(
            decoration: BoxDecoration(
              color: zt.bgPrimary,
              borderRadius: BorderRadius.circular(ZendRadii.lg),
              border: Border.all(color: amountError != null ? ZendColors.destructive : zt.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text('\$', style: TextStyle(fontFamily: 'DMMono', fontSize: 20, color: zt.textSecondary)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: customCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 20, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(fontFamily: 'DMMono', fontSize: 20, color: zt.textSecondary.withValues(alpha: 0.4)),
                      border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (amountError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(amountError!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: ZendColors.destructive)),
            ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 12),
        // Custom amount toggle
        GestureDetector(
          onTap: onToggleCustom,
          child: Text(
            customMode ? 'Use stepper instead' : 'Custom amount',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.accent,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        // Next button
        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: zt.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            'Choose a sticker',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Step 2: Sticker ───────────────────────────────────────────────────────────

class _StickerStep extends StatelessWidget {
  const _StickerStep({
    required this.zt,
    required this.stickers,
    required this.loading,
    required this.selected,
    required this.onSelect,
    required this.onConfirm,
  });

  final ZendTheme zt;
  final List<VibeSticker> stickers;
  final bool loading;
  final VibeSticker? selected;
  final ValueChanged<VibeSticker> onSelect;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: stickers.length,
          itemBuilder: (context, i) {
            final sticker = stickers[i];
            final isSelected = selected?.id == sticker.id;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(sticker);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: isSelected ? zt.accent.withValues(alpha: 0.15) : zt.bgPrimary,
                  borderRadius: BorderRadius.circular(ZendRadii.lg),
                  border: Border.all(
                    color: isSelected ? zt.accent : zt.border.withValues(alpha: 0.5),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(sticker.emoji, style: TextStyle(fontSize: isSelected ? 28 : 24)),
                    const SizedBox(height: 3),
                    Text(
                      sticker.label,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 9,
                        color: isSelected ? zt.accent : zt.textSecondary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: selected != null ? onConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: selected != null ? zt.accent : zt.border,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Preview', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Step 3: Preview ───────────────────────────────────────────────────────────

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.zt,
    required this.amount,
    required this.sticker,
    required this.onSend,
  });

  final ZendTheme zt;
  final double amount;
  final VibeSticker? sticker;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview card
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          alignment: Alignment.center,
          child: Column(
            children: [
              Text(sticker?.emoji ?? '✨', style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: zt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                  border: Border.all(color: zt.accent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '\$${amount.toStringAsFixed(2)} hidden ✨',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.accent, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Amount revealed when recipient taps',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: onSend,
          style: ElevatedButton.styleFrom(
            backgroundColor: zt.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(sticker?.emoji ?? '✨', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Send Vibe', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}
