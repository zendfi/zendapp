import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/pocket_models.dart';
import 'package:solar_icons/solar_icons.dart';

enum _GoalStage { nameEmoji, targetDeadline, mode, confirm }

class GoalCreationSheet extends StatefulWidget {
  const GoalCreationSheet({super.key});

  @override
  State<GoalCreationSheet> createState() => _GoalCreationSheetState();
}

class _GoalCreationSheetState extends State<GoalCreationSheet> {
  _GoalStage _stage = _GoalStage.nameEmoji;

  // Stage 1
  final _nameController = TextEditingController();
  String _selectedEmoji = '🎯';
  String? _nameError;

  // Stage 2
  String _targetInput = '';
  String? _targetError;
  DateTime? _deadline;

  // Stage 3
  String _mode = 'flexible'; // "flexible" | "strict"

  // Stage 4 (confirm + PIN)
  String _pinDigits = '';
  String? _pinError;
  String? _errorMessage;
  bool _processing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  double get _parsedTarget {
    if (_targetInput.isEmpty) return 0.0;
    return double.tryParse(_targetInput) ?? 0.0;
  }

  bool get _nameValid =>
      _nameController.text.trim().isNotEmpty &&
      _nameController.text.trim().length <= 40;

  bool get _targetValid => _parsedTarget >= 1.0;

  void _onTargetKey(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _targetError = null;
      if (key == 'del') {
        if (_targetInput.isNotEmpty) {
          _targetInput = _targetInput.substring(0, _targetInput.length - 1);
        }
        return;
      }
      if (key == '.' && _targetInput.contains('.')) return;
      if (key == '.' && _targetInput.isEmpty) {
        _targetInput = '0.';
        return;
      }
      final dotIdx = _targetInput.indexOf('.');
      if (dotIdx >= 0 && _targetInput.length - dotIdx > 2) return;
      _targetInput += key;
    });
  }

  void _onPinKey(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _pinError = null;
      if (key == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }
      if (_pinDigits.length >= 4) return;
      _pinDigits += key;
    });
    if (_pinDigits.length == 4) {
      _submitGoal();
    }
  }

  Future<void> _submitGoal() async {
    setState(() => _processing = true);

    try {
      final model = ZendScope.of(context);
      final req = CreateGoalRequest(
        name: _nameController.text.trim(),
        emoji: _selectedEmoji,
        targetUsd: _parsedTarget,
        deadline: _deadline?.toIso8601String().split('T').first,
        mode: _mode,
      );

      // We need to sign nothing for goal creation — it's a pure DB operation.
      // But we still verify the PIN to confirm user intent.
      await model.walletService.verifyLocalPin(_pinDigits);

      final pocket = await model.pocketService.createGoal(req);

      if (!mounted) return;
      Navigator.of(context).pop(pocket);
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _processing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _processing = false;
        _pinDigits = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _processing = false;
        _pinDigits = '';
      });
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() => _deadline = picked);
    }
  }

  double get _heightFactor => switch (_stage) {
        _GoalStage.nameEmoji => 0.85,
        _GoalStage.targetDeadline => 0.82,
        _GoalStage.mode => 0.65,
        _GoalStage.confirm => 0.72,
      };

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: !_processing,
      child: Container(
        height: screenHeight * _heightFactor,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.xxl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            const ZendSheetHandle(),
            const SizedBox(height: 8),
            Expanded(child: _buildStage()),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    if (_processing) {
      return const Center(
        child: ZendLoader(color: ZendColors.accentBright),
      );
    }

    return switch (_stage) {
      _GoalStage.nameEmoji => _NameEmojiStage(
          nameController: _nameController,
          selectedEmoji: _selectedEmoji,
          nameError: _nameError,
          onEmojiSelected: (e) => setState(() => _selectedEmoji = e),
          onContinue: () {
            if (!_nameValid) {
              setState(() => _nameError = _nameController.text.trim().isEmpty
                  ? 'Enter a goal name'
                  : 'Name must be 40 characters or less');
              return;
            }
            setState(() {
              _nameError = null;
              _stage = _GoalStage.targetDeadline;
            });
          },
        ),
      _GoalStage.targetDeadline => _TargetDeadlineStage(
          targetInput: _targetInput,
          targetError: _targetError,
          deadline: _deadline,
          targetValid: _targetValid,
          onKey: _onTargetKey,
          onPickDeadline: _pickDeadline,
          onClearDeadline: () => setState(() => _deadline = null),
          onContinue: () {
            if (!_targetValid) {
              setState(() => _targetError = 'Enter a target of at least \$1');
              return;
            }
            setState(() {
              _targetError = null;
              _stage = _GoalStage.mode;
            });
          },
          onBack: () => setState(() => _stage = _GoalStage.nameEmoji),
        ),
      _GoalStage.mode => _ModeStage(
          selectedMode: _mode,
          onModeSelected: (m) => setState(() => _mode = m),
          onContinue: () => setState(() => _stage = _GoalStage.confirm),
          onBack: () => setState(() => _stage = _GoalStage.targetDeadline),
        ),
      _GoalStage.confirm => _ConfirmStage(
          name: _nameController.text.trim(),
          emoji: _selectedEmoji,
          targetUsd: _parsedTarget,
          deadline: _deadline,
          mode: _mode,
          pinDigits: _pinDigits,
          pinError: _pinError,
          errorMessage: _errorMessage,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _errorMessage = null;
            _stage = _GoalStage.mode;
          }),
        ),
    };
  }
}

// ── Stage 1: Name + Emoji ─────────────────────────────────────────────────────

class _NameEmojiStage extends StatelessWidget {
  const _NameEmojiStage({
    required this.nameController,
    required this.selectedEmoji,
    required this.nameError,
    required this.onEmojiSelected,
    required this.onContinue,
  });

  final TextEditingController nameController;
  final String selectedEmoji;
  final String? nameError;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onContinue;

  static const _commonEmojis = [
    '🎯', '🏠', '🚗', '✈️', '💍', '🎓', '💻', '📱',
    '🏋️', '🌴', '🎸', '📚', '🐶', '🍕', '⚽', '🎮',
    '💎', '🌟', '🎁', '🏖️', '🚀', '🎨', '🏔️', '🌈',
    '💰', '🎪', '🦋', '🌺', '🍀', '🎵',
  ];

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Name your goal',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),

          // ── Name field ────────────────────────────────────────────
          TextField(
            controller: nameController,
            maxLength: 40,
            decoration: InputDecoration(
              hintText: 'e.g. New car, Holiday fund…',
              hintStyle: TextStyle(
                fontFamily: 'DMSans',
                color: zt.textSecondary,
              ),
              errorText: nameError,
              filled: true,
              fillColor: zt.bgSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZendRadii.md),
                borderSide: BorderSide.none,
              ),
              counterStyle: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11,
                color: zt.textSecondary,
              ),
            ),
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 16,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.md),

          // ── Emoji picker ──────────────────────────────────────────
          Text(
            'Pick an emoji',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xs),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _commonEmojis.length,
              itemBuilder: (context, i) {
                final emoji = _commonEmojis[i];
                final isSelected = emoji == selectedEmoji;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onEmojiSelected(emoji);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? ZendColors.accentBright.withValues(alpha: 0.2)
                          : zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.md),
                      border: isSelected
                          ? Border.all(color: ZendColors.accentBright, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: ZendSpacing.md),

          PrimaryButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

// ── Stage 2: Target + Deadline ────────────────────────────────────────────────

class _TargetDeadlineStage extends StatelessWidget {
  const _TargetDeadlineStage({
    required this.targetInput,
    required this.targetError,
    required this.deadline,
    required this.targetValid,
    required this.onKey,
    required this.onPickDeadline,
    required this.onClearDeadline,
    required this.onContinue,
    required this.onBack,
  });

  final String targetInput;
  final String? targetError;
  final DateTime? deadline;
  final bool targetValid;
  final ValueChanged<String> onKey;
  final VoidCallback onPickDeadline;
  final VoidCallback onClearDeadline;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  String get _displayAmount =>
      targetInput.isEmpty ? '\$0' : '\$$targetInput';

  String _formatDate(DateTime d) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Set your target',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),

          Center(
            child: Text(
              _displayAmount,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
          ),
          if (targetError != null)
            Center(
              child: Text(
                targetError!,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.destructive,
                ),
              ),
            ),
          const SizedBox(height: ZendSpacing.sm),

          // ── Deadline picker ───────────────────────────────────────
          GestureDetector(
            onTap: onPickDeadline,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: ZendSpacing.md, vertical: ZendSpacing.sm),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.md),
              ),
              child: Row(
                children: [
                  Icon(SolarIconsBold.calendar,
                      size: 16, color: zt.textSecondary),
                  const SizedBox(width: ZendSpacing.xs),
                  Expanded(
                    child: Text(
                      deadline != null
                          ? _formatDate(deadline!)
                          : 'Set a deadline (optional)',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        color: deadline != null
                            ? zt.textPrimary
                            : zt.textSecondary,
                      ),
                    ),
                  ),
                  if (deadline != null)
                    GestureDetector(
                      onTap: onClearDeadline,
                      child: Icon(SolarIconsBold.closeCircle, size: 16, color: zt.textSecondary),
                    ),
                ],
              ),
            ),
          ),

          const Spacer(),
          _NumericKeypad(onKey: onKey),
          const SizedBox(height: ZendSpacing.md),
          PrimaryButton(
            label: 'Continue',
            onPressed: targetValid ? onContinue : null,
          ),
        ],
      ),
    );
  }
}

// ── Stage 3: Mode ─────────────────────────────────────────────────────────────

class _ModeStage extends StatelessWidget {
  const _ModeStage({
    required this.selectedMode,
    required this.onModeSelected,
    required this.onContinue,
    required this.onBack,
  });

  final String selectedMode;
  final ValueChanged<String> onModeSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose a saving style',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xl),

          _ModeOption(
            title: 'Flexible',
            description: 'Withdraw anytime, even before you hit your goal.',
            icon: SolarIconsBold.cardSend,
            isSelected: selectedMode == 'flexible',
            onTap: () => onModeSelected('flexible'),
            zt: zt,
          ),
          const SizedBox(height: ZendSpacing.sm),
          _ModeOption(
            title: 'Strict',
            description: 'Locked until you reach your target. Keeps you on track.',
            icon: SolarIconsBold.lockKeyhole,
            isSelected: selectedMode == 'strict',
            onTap: () => onModeSelected('strict'),
            zt: zt,
          ),

          const Spacer(),
          PrimaryButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.zt,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(ZendSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? ZendColors.accentBright.withValues(alpha: 0.1)
              : zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.xl),
          border: isSelected
              ? Border.all(color: ZendColors.accentBright, width: 2)
              : Border.all(color: zt.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? ZendColors.accentBright.withValues(alpha: 0.2)
                    : zt.bgPrimary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? ZendColors.accentBright : zt.textSecondary,
              ),
            ),
            const SizedBox(width: ZendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(SolarIconsBold.checkCircle, color: ZendColors.accentBright, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Stage 4: Confirm + PIN ────────────────────────────────────────────────────

class _ConfirmStage extends StatelessWidget {
  const _ConfirmStage({
    required this.name,
    required this.emoji,
    required this.targetUsd,
    required this.deadline,
    required this.mode,
    required this.pinDigits,
    required this.pinError,
    required this.errorMessage,
    required this.onKey,
    required this.onBack,
  });

  final String name;
  final String emoji;
  final double targetUsd;
  final DateTime? deadline;
  final String mode;
  final String pinDigits;
  final String? pinError;
  final String? errorMessage;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  String _formatDate(DateTime d) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),

          // ── Summary ───────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ZendSpacing.md),
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.xl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji $name',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: zt.textPrimary,
                  ),
                ),
                const SizedBox(height: ZendSpacing.xs),
                Text(
                  'Target: \$${targetUsd.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 14,
                    color: zt.textSecondary,
                  ),
                ),
                if (deadline != null)
                  Text(
                    'Deadline: ${_formatDate(deadline!)}',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: zt.textSecondary,
                    ),
                  ),
                Text(
                  'Mode: ${mode == 'strict' ? 'Strict' : 'Flexible'}',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZendSpacing.xl),

          // ── PIN dots ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < pinDigits.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? zt.textPrimary : zt.bgSecondary,
                  border: Border.all(color: zt.border),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            errorMessage ?? pinError ?? 'Confirm with your PIN',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: (pinError != null || errorMessage != null)
                  ? ZendColors.destructive
                  : zt.textSecondary,
            ),
          ),
          const Spacer(),
          _NumericKeypad(onKey: onKey),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Numeric keypad ────────────────────────────────────────────────────────────

class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({required this.onKey});
  final ValueChanged<String> onKey;

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      children: _keys.map((row) {
        return Row(
          children: row.map((key) {
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => onKey(key),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  child: key == 'del'
                      ? ZendBackspaceIcon(color: zt.textPrimary, size: 20)
                      : Text(
                          key,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: zt.textPrimary,
                          ),
                        ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
