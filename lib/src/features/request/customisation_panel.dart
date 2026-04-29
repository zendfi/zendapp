import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'payment_request.dart';
import 'request_utils.dart';

class CustomisationPanel extends StatefulWidget {
  const CustomisationPanel({
    super.key,
    required this.onConfirm,
    this.initial,
  });

  final ValueChanged<RequestCustomisation> onConfirm;
  final RequestCustomisation? initial;

  @override
  State<CustomisationPanel> createState() => _CustomisationPanelState();
}

class _CustomisationPanelState extends State<CustomisationPanel> {
  static const int _noteMaxLength = 280;

  static const List<Color> _paletteColors = [
    ZendColors.accent,
    ZendColors.accentBright,
    ZendColors.accentPop,
    ZendColors.destructive,
    Color(0xFF4A90D9),
    Color(0xFFE8A838),
  ];

  late final TextEditingController _noteController;
  Color? _selectedColor;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(
      text: widget.initial?.personalNote ?? '',
    );
    _selectedColor = widget.initial?.themeColor;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _onDone() {
    widget.onConfirm(
      RequestCustomisation(
        personalNote: _noteController.text.trim(),
        themeColor: _selectedColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = remainingCharacters(_noteController.text, _noteMaxLength);

    return Container(
      padding: const EdgeInsets.all(ZendSpacing.md),
      decoration: BoxDecoration(
        color: ZendColors.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Personal note',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ZendColors.textSecondary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xs),
          TextField(
            controller: _noteController,
            maxLines: 3,
            minLines: 2,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_noteMaxLength),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Add a personal message...',
              hintStyle: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: ZendColors.textSecondary,
              ),
              filled: true,
              fillColor: ZendColors.bgPrimary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZendRadii.sm),
                borderSide: const BorderSide(color: ZendColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZendRadii.sm),
                borderSide: const BorderSide(color: ZendColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZendRadii.sm),
                borderSide: const BorderSide(color: ZendColors.accent),
              ),
              contentPadding: const EdgeInsets.all(ZendSpacing.sm),
            ),
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xxs),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$remaining characters remaining',
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: remaining < 30
                    ? ZendColors.destructive
                    : ZendColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: ZendSpacing.md),
          const Text(
            'Theme colour',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ZendColors.textSecondary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xs),
          Row(
            children: _paletteColors.map((color) {
              final isSelected = _selectedColor == color;
              return Padding(
                padding: const EdgeInsets.only(right: ZendSpacing.xs),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedColor = isSelected ? null : color;
                  }),
                  child: AnimatedContainer(
                    duration: ZendMotion.tabSwitch,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: ZendColors.textPrimary, width: 2.5)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: ZendSpacing.lg),
          PrimaryButton(
            label: 'Done',
            onPressed: _onDone,
          ),
        ],
      ),
    );
  }
}
