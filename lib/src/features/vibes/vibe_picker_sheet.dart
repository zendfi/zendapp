import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import 'vibe_sticker_catalog.dart';
import 'package:solar_icons/solar_icons.dart';

/// Bottom sheet sticker grid + amount input for sending a Vibe.
///
/// Usage:
///   final result = await showVibePickerSheet(context, roomId: roomId);
///   // result is a VibeSendResult if the user confirmed, null if dismissed.
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

class _VibePickerSheet extends StatefulWidget {
  const _VibePickerSheet({required this.roomId});
  final String roomId;

  @override
  State<_VibePickerSheet> createState() => _VibePickerSheetState();
}

class _VibePickerSheetState extends State<_VibePickerSheet> {
  List<VibeSticker> _stickers = [];
  bool _loading = true;
  VibeSticker? _selected;
  final _amountController = TextEditingController();
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadStickers() async {
    final catalog = VibeStickerCatalog.instance;
    final stickers = await catalog.getStickers(ZendScope.of(context));
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _loading = false;
      });
    }
  }

  void _selectSticker(VibeSticker sticker) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = sticker;
      _amountError = null;
    });
  }

  void _confirm() {
    final raw = _amountController.text.trim();
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a valid amount');
      return;
    }
    if (amount < 0.01) {
      setState(() => _amountError = 'Minimum is \$0.01');
      return;
    }
    if (amount > 5.00) {
      setState(() => _amountError = 'Maximum is \$5.00 per Vibe');
      return;
    }
    if (_selected == null) {
      setState(() => _amountError = 'Pick a sticker first');
      return;
    }
    Navigator.of(context).pop(VibeSendResult(
      stickerId: _selected!.id,
      stickerEmoji: _selected!.emoji,
      stickerLabel: _selected!.label,
      amountUsdc: amount,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.xxl),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: zt.border,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: zt.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(SolarIconsBold.gift, size: 16, color: zt.accent),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send a Vibe',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    Text(
                      'Amount hidden until they tap ✨',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 10,
                        color: zt.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '\$0.01 – \$5',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Sticker grid
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _stickers.length,
                itemBuilder: (context, i) {
                  final sticker = _stickers[i];
                  final isSelected = _selected?.id == sticker.id;
                  return GestureDetector(
                    onTap: () => _selectSticker(sticker),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? zt.accent.withValues(alpha: 0.18)
                            : zt.bgPrimary,
                        borderRadius: BorderRadius.circular(ZendRadii.lg),
                        border: Border.all(
                          color: isSelected
                              ? zt.accent
                              : zt.border.withValues(alpha: 0.6),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            sticker.emoji,
                            style: TextStyle(
                              fontSize: isSelected ? 28 : 24,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sticker.label,
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 9,
                              color: isSelected
                                  ? zt.accent
                                  : zt.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
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

            const SizedBox(height: 16),

            // Amount input + confirm
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: zt.bgPrimary,
                          borderRadius: BorderRadius.circular(ZendRadii.md),
                          border: Border.all(
                            color: _amountError != null
                                ? ZendColors.destructive
                                : zt.border,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Text(
                              '\$',
                              style: TextStyle(
                                fontFamily: 'DMMono',
                                fontSize: 16,
                                color: zt.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(
                                  fontFamily: 'DMMono',
                                  fontSize: 16,
                                  color: zt.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  hintStyle: TextStyle(
                                    fontFamily: 'DMMono',
                                    fontSize: 16,
                                    color: zt.textSecondary.withValues(
                                        alpha: 0.5),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) {
                                  if (_amountError != null) {
                                    setState(() => _amountError = null);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_amountError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _amountError!,
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            color: ZendColors.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _confirm,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _selected != null
                          ? zt.accent
                          : zt.border,
                      borderRadius: BorderRadius.circular(ZendRadii.md),
                    ),
                    child: Text(
                      'Send',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _selected != null
                            ? ZendColors.textOnDeep
                            : zt.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
