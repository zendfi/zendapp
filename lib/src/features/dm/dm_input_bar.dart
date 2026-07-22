import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_tokens.dart';
import '../vibes/vibe_picker_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

/// Callback types for the three DM actions
typedef OnRequestPayment = void Function();
typedef OnPayRecipient = void Function();

/// The DM input bar — compact single-line bar with a `+` action panel.
///
/// When the `+` button is tapped, a keyboard-height panel slides up
/// seamlessly: it matches the keyboard height so there's no layout
/// disruption when toggling between typing and actions.
class DmInputBar extends StatefulWidget {
  const DmInputBar({
    super.key,
    required this.onSend,
    required this.onTyping,
    required this.roomId,
    this.onSendVibe,
    this.onRequestPayment,
    this.onPayRecipient,
  });

  final ValueChanged<String> onSend;
  final ValueChanged<bool> onTyping;
  final String roomId;
  final ValueChanged<VibeSendResult>? onSendVibe;
  final OnRequestPayment? onRequestPayment;
  final OnPayRecipient? onPayRecipient;

  @override
  State<DmInputBar> createState() => _DmInputBarState();
}

class _DmInputBarState extends State<DmInputBar>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _typingDebounce;
  bool _hasText = false;
  bool _panelOpen = false;
  double _keyboardHeight = 0;

  late final AnimationController _panelCtrl;
  late final Animation<double> _panelAnim;

  @override
  void initState() {
    super.initState();
    _panelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _panelAnim = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOut);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _panelOpen) {
        _closePanel();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _typingDebounce?.cancel();
    _panelCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture keyboard height whenever it changes (non-zero = keyboard visible)
    final kb = MediaQuery.of(context).viewInsets.bottom;
    if (kb > 50) _keyboardHeight = kb; // keep the last known keyboard height
  }

  void _onChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    widget.onTyping(true);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () => widget.onTyping(false));
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _ctrl.clear();
    setState(() => _hasText = false);
    widget.onTyping(false);
    _typingDebounce?.cancel();
    widget.onSend(text);
  }

  void _togglePanel() {
    if (_panelOpen) {
      _closePanel();
    } else {
      _openPanel();
    }
  }

  void _openPanel() {
    _focusNode.unfocus();
    setState(() => _panelOpen = true);
    _panelCtrl.forward();
  }

  void _closePanel() {
    _panelCtrl.reverse().then((_) {
      if (mounted) setState(() => _panelOpen = false);
    });
  }

  double get _panelHeight {
    // Use last known keyboard height, with a sensible fallback
    final kh = _keyboardHeight > 50 ? _keyboardHeight : 260.0;
    return kh;
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final viewPadding = MediaQuery.of(context).viewPadding.bottom;

    // When the real keyboard is visible and panel is open, close the panel
    if (_panelOpen && viewInsets > 50) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _panelOpen) _closePanel();
      });
    }

    // Bottom padding: when keyboard is up use viewInsets, else if panel open
    // use panel height, else just safe area
    final bottomPad = _panelOpen
        ? 0.0
        : (viewInsets > 0 ? 0.0 : viewPadding * 0.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Input row ──
        Container(
          padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomPad),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: zt.border.withValues(alpha: 0.6), width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // + button
              GestureDetector(
                onTap: _togglePanel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: BoxDecoration(
                    color: _panelOpen
                        ? zt.accent.withValues(alpha: 0.15)
                        : zt.bgSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      _panelOpen
                          ? SolarIconsBold.closeCircle
                          : SolarIconsBold.addCircle,
                      key: ValueKey(_panelOpen),
                      size: 20,
                      color: _panelOpen ? zt.accent : zt.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
                  decoration: BoxDecoration(
                    color: zt.bgSecondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _send(),
                    maxLines: null,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      color: zt.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: zt.textSecondary.withValues(alpha: 0.7),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Send / mic button
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _hasText
                    ? GestureDetector(
                        key: const ValueKey('send'),
                        onTap: _send,
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(bottom: 1),
                          decoration: BoxDecoration(
                            color: zt.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(SolarIconsBold.plain, size: 18, color: Colors.white),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('spacer'),
                        width: 36,
                        height: 36,
                      ),
              ),
            ],
          ),
        ),

        // ── Action panel ──
        SizeTransition(
          sizeFactor: _panelAnim,
          axisAlignment: 1.0,
          child: Container(
            height: _panelHeight,
            color: zt.bgSecondary,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: zt.border,
                          borderRadius: BorderRadius.circular(ZendRadii.pill),
                        ),
                      ),
                    ),
                    // Action grid
                    Row(
                      children: [
                        _ActionTile(
                          icon: SolarIconsBold.squareArrowRightDown,
                          label: 'Request',
                          color: const Color(0xFF6C63FF),
                          onTap: () {
                            _closePanel();
                            widget.onRequestPayment?.call();
                          },
                        ),
                        const SizedBox(width: 12),
                        _ActionTile(
                          icon: SolarIconsBold.dollar,
                          label: 'Pay',
                          color: const Color(0xFF4ADE80),
                          onTap: () {
                            _closePanel();
                            widget.onPayRecipient?.call();
                          },
                        ),
                        const SizedBox(width: 12),
                        _ActionTile(
                          icon: SolarIconsBold.gift,
                          label: 'Vibe',
                          color: const Color(0xFFFF6B9D),
                          onTap: () async {
                            _closePanel();
                            if (widget.onSendVibe == null) return;
                            await Future.delayed(const Duration(milliseconds: 260));
                            if (!mounted) return;
                            final result = await showVibePickerSheet(
                              context, // ignore: use_build_context_synchronously
                              roomId: widget.roomId,
                            );
                            if (result != null && mounted) {
                              HapticFeedback.mediumImpact();
                              widget.onSendVibe!(result);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ZendRadii.xl),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: zt.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
