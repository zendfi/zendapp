import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../vibes/vibe_picker_sheet.dart';
import '../vibes/vibe_sticker_catalog.dart';
import 'package:solar_icons/solar_icons.dart';

typedef OnRequestPayment = void Function();
typedef OnPayRecipient = void Function();

enum _PanelMode { none, actions, vibeAmount, vibeSticker, vibePreview }

/// The DM input bar with an inline keyboard-height panel.
/// When Vibe is selected the panel morphs step-by-step into the Vibe creator.
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
  double _keyboardHeight = 0;

  // Panel state
  _PanelMode _mode = _PanelMode.none;
  _PanelMode _prevMode = _PanelMode.none; // used to determine slide direction
  late final AnimationController _panelCtrl;
  late final Animation<double> _panelAnim;

  // Vibe creator state
  double _vibeAmount = 1.0;
  bool _vibeCustomMode = false;
  String _vibeCustomInput = '';
  List<VibeSticker> _stickers = [];
  bool _stickersLoading = true;
  VibeSticker? _selectedSticker;

  void _setMode(_PanelMode next) {
    setState(() {
      _prevMode = _mode;
      _mode = next;
    });
  }

  bool get _panelOpen => _mode != _PanelMode.none;

  @override
  void initState() {
    super.initState();
    _panelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _panelAnim = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOut);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _panelOpen) _closePanel();
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
    final kb = MediaQuery.of(context).viewInsets.bottom;
    if (kb > 50) _keyboardHeight = kb;
  }

  // ── Text input ──────────────────────────────────────────────────────────────

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

  // ── Panel lifecycle ─────────────────────────────────────────────────────────

  void _openActions() {
    _focusNode.unfocus();
    _setMode(_PanelMode.actions);
    _panelCtrl.forward();
  }

  void _closePanel() {
    _panelCtrl.reverse().then((_) {
      if (mounted) _setMode(_PanelMode.none);
    });
  }

  void _togglePanel() {
    if (_panelOpen) {
      _closePanel();
    } else {
      _openActions();
    }
  }

  void _enterVibeFlow() {
    _setMode(_PanelMode.vibeAmount);
    if (_stickersLoading) _loadStickers();
  }

  Future<void> _loadStickers() async {
    final catalog = VibeStickerCatalog.instance;
    final stickers = await catalog.getStickers(ZendScope.of(context));
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _stickersLoading = false;
        if (stickers.isNotEmpty) _selectedSticker ??= stickers.first;
      });
    }
  }

  // ── Vibe flow ───────────────────────────────────────────────────────────────

  double get _resolvedAmount {
    if (_vibeCustomMode) {
      return double.tryParse(_vibeCustomInput) ?? _vibeAmount;
    }
    return _vibeAmount;
  }

  void _confirmVibeAmount() {
    final a = _resolvedAmount;
    if (a < 0.01 || a > 5.0) return;
    _vibeAmount = a;
    _setMode(_PanelMode.vibeSticker);
  }

  void _confirmVibeSticker() {
    if (_selectedSticker == null) return;
    _setMode(_PanelMode.vibePreview);
  }

  void _sendVibe() {
    if (_selectedSticker == null || widget.onSendVibe == null) return;
    HapticFeedback.mediumImpact();
    final result = VibeSendResult(
      stickerId: _selectedSticker!.id,
      stickerEmoji: _selectedSticker!.emoji,
      stickerLabel: _selectedSticker!.label,
      amountUsdc: _vibeAmount,
    );
    // Reset state
    setState(() {
      _vibeAmount = 1.0;
      _vibeCustomMode = false;
      _vibeCustomInput = '';
      _selectedSticker = _stickers.isNotEmpty ? _stickers.first : null;
    });
    _closePanel();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) widget.onSendVibe!(result);
    });
  }

  void _onKeypadTap(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == '⌫') {
        if (_vibeCustomInput.isNotEmpty) {
          _vibeCustomInput = _vibeCustomInput.substring(0, _vibeCustomInput.length - 1);
        }
      } else if (key == '.') {
        if (!_vibeCustomInput.contains('.')) _vibeCustomInput += '.';
      } else {
        // Max 4 chars before decimal, 2 after
        final parts = _vibeCustomInput.split('.');
        if (parts.length == 1 && parts[0].isNotEmpty && parts[0] == '5') return; // cap at 5
        if (parts.length == 2 && parts[1].length >= 2) return;
        _vibeCustomInput += key;
      }
    });
  }

  double get _panelHeight {
    final kh = _keyboardHeight > 50 ? _keyboardHeight : 270.0;
    // Custom amount keypad needs a bit more room
    if (_mode == _PanelMode.vibeAmount && _vibeCustomMode) return kh + 30;
    return kh;
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final viewPadding = MediaQuery.of(context).viewPadding.bottom;

    if (_panelOpen && viewInsets > 50) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _panelOpen) _closePanel();
      });
    }

    final bottomPad = _panelOpen ? 0.0 : (viewInsets > 0 ? 0.0 : viewPadding * 0.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Input row ────────────────────────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomPad),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: zt.border.withValues(alpha: 0.6), width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _togglePanel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36, height: 36,
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: BoxDecoration(
                    color: _panelOpen ? zt.accent.withValues(alpha: 0.15) : zt.bgSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      _panelOpen ? SolarIconsBold.closeCircle : SolarIconsBold.addCircle,
                      key: ValueKey(_panelOpen),
                      size: 20,
                      color: _panelOpen ? zt.accent : zt.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
                  decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: TextField(
                    controller: _ctrl, focusNode: _focusNode,
                    onChanged: _onChanged, onSubmitted: (_) => _send(),
                    maxLines: null,
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textSecondary.withValues(alpha: 0.7)),
                      border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _hasText
                    ? GestureDetector(
                        key: const ValueKey('send'),
                        onTap: _send,
                        child: Container(
                          width: 36, height: 36,
                          margin: const EdgeInsets.only(bottom: 1),
                          decoration: BoxDecoration(color: zt.accent, shape: BoxShape.circle),
                          child: const Icon(SolarIconsBold.plain, size: 18, color: Colors.white),
                        ),
                      )
                    : const SizedBox(key: ValueKey('spacer'), width: 36, height: 36),
              ),
            ],
          ),
        ),

        // ── Action / Vibe panel ───────────────────────────────────────────────
        SizeTransition(
          sizeFactor: _panelAnim,
          axisAlignment: 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: _panelHeight,
            color: zt.bgSecondary,
            child: SafeArea(
              top: false,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, anim) {
                    // Slide right→left when going forward (deeper into Vibe flow),
                    // left→right when going back.
                    final isForward = _mode.index >= _prevMode.index;
                    final beginOffset = Offset(isForward ? 1.0 : -1.0, 0);
                    final endOffset = Offset.zero;
                    // Outgoing slides the opposite direction
                    final isIncoming = child.key == ValueKey(_mode);
                    final slideBegin = isIncoming ? beginOffset : Offset(-beginOffset.dx, 0);
                    return SlideTransition(
                      position: Tween<Offset>(begin: slideBegin, end: endOffset)
                          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                      child: child,
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    children: [
                      ...previousChildren,
                      ?currentChild,
                    ],
                  ),
                  child: KeyedSubtree(key: ValueKey(_mode), child: _buildPanelContent(zt)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanelContent(ZendTheme zt) {
    return switch (_mode) {
      _PanelMode.actions || _PanelMode.none => _buildActionsPanel(zt),
      _PanelMode.vibeAmount => _buildVibeAmountPanel(zt),
      _PanelMode.vibeSticker => _buildVibeStickerPanel(zt),
      _PanelMode.vibePreview => _buildVibePreviewPanel(zt),
    };
  }

  // ── Panel content builders ──────────────────────────────────────────────────

  Widget _buildActionsPanel(ZendTheme zt) {
    return Padding(
      key: const ValueKey('actions'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(zt),
          const SizedBox(height: 20),
          Row(
            children: [
              _ActionTile(icon: SolarIconsBold.squareArrowRightDown, label: 'Request',
                color: const Color(0xFF6C63FF),
                onTap: () { _closePanel(); widget.onRequestPayment?.call(); }),
              const SizedBox(width: 12),
              _ActionTile(icon: SolarIconsBold.dollar, label: 'Pay',
                color: const Color(0xFF4ADE80),
                onTap: () { _closePanel(); widget.onPayRecipient?.call(); }),
              const SizedBox(width: 12),
              _ActionTile(icon: SolarIconsBold.gift, label: 'Vibe',
                color: const Color(0xFFFF6B9D),
                onTap: _enterVibeFlow),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVibeAmountPanel(ZendTheme zt) {

    return Padding(
      key: const ValueKey('vibeAmount'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              GestureDetector(
                onTap: () => _setMode(_PanelMode.actions),
                child: Icon(SolarIconsBold.altArrowLeft, color: zt.textSecondary, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Vibe amount', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700, color: zt.textPrimary))),
              Text('\$0.01 – \$5', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          if (!_vibeCustomMode) ...[
            // Stepper
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepBtn(zt, '-', _vibeAmount > 0.01 ? () => setState(() => _vibeAmount = (_vibeAmount - 1).clamp(0.01, 5.0)) : null),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: () => setState(() { _vibeCustomMode = true; _vibeCustomInput = _vibeAmount.toStringAsFixed(2); }),
                  child: Text('\$${_vibeAmount.toStringAsFixed(_vibeAmount == _vibeAmount.roundToDouble() ? 0 : 2)}',
                    style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 44, fontStyle: FontStyle.italic, color: zt.textPrimary, height: 1)),
                ),
                const SizedBox(width: 20),
                _stepBtn(zt, '+', _vibeAmount < 5.0 ? () => setState(() => _vibeAmount = (_vibeAmount + 1).clamp(0.01, 5.0)) : null),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(child: GestureDetector(
                  onTap: () => setState(() { _vibeCustomMode = true; _vibeCustomInput = ''; }),
                  child: Text('Custom amount', textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.accent, fontWeight: FontWeight.w600)),
                )),
                const SizedBox(width: 12),
                Expanded(child: _primaryBtn(zt, 'Pick sticker', const Color(0xFFFF6B9D), _confirmVibeAmount)),
              ],
            ),
          ] else ...[
            // On-screen keypad
            Text(_vibeCustomInput.isEmpty ? '0' : '\$$_vibeCustomInput',
              style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 36, fontStyle: FontStyle.italic,
                color: _resolvedAmount > 5 ? ZendColors.destructive : zt.textPrimary, height: 1.1)),
            if (_resolvedAmount > 5)
              Text('Max \$5.00', style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: ZendColors.destructive)),
            const SizedBox(height: 6),
            _keypad(zt),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _vibeCustomMode = false; _vibeCustomInput = ''; }),
                child: Text('Use stepper', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.accent, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: _primaryBtn(zt, 'Pick sticker', const Color(0xFFFF6B9D),
                _resolvedAmount >= 0.01 && _resolvedAmount <= 5 ? () { _vibeAmount = _resolvedAmount; _confirmVibeAmount(); } : null)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildVibeStickerPanel(ZendTheme zt) {
    return Padding(
      key: const ValueKey('vibeSticker'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(onTap: () => _setMode(_PanelMode.vibeAmount),
                child: Icon(SolarIconsBold.altArrowLeft, color: zt.textSecondary, size: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text('Pick a sticker', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700, color: zt.textPrimary))),
              Text('\$${_vibeAmount.toStringAsFixed(2)}', style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.accent, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (_stickersLoading)
            const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else
            Expanded(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: _stickers.length,
                itemBuilder: (ctx, i) {
                  final s = _stickers[i];
                  final sel = _selectedSticker?.id == s.id;
                  return GestureDetector(
                    onTap: () { HapticFeedback.selectionClick(); setState(() => _selectedSticker = s); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFFF6B9D).withValues(alpha: 0.15) : zt.bgPrimary,
                        borderRadius: BorderRadius.circular(ZendRadii.lg),
                        border: Border.all(color: sel ? const Color(0xFFFF6B9D) : zt.border.withValues(alpha: 0.4), width: sel ? 2 : 1),
                      ),
                      child: Center(child: Text(s.emoji, style: TextStyle(fontSize: sel ? 24 : 20))),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          _primaryBtn(zt, 'Preview', const Color(0xFFFF6B9D), _selectedSticker != null ? _confirmVibeSticker : null),
        ],
      ),
    );
  }

  Widget _buildVibePreviewPanel(ZendTheme zt) {
    return Padding(
      key: const ValueKey('vibePreview'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(onTap: () => _setMode(_PanelMode.vibeSticker),
                child: Icon(SolarIconsBold.altArrowLeft, color: zt.textSecondary, size: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text('Ready to send', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700, color: zt.textPrimary))),
            ],
          ),
          const Spacer(),
          Text(_selectedSticker?.emoji ?? '✨', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B9D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              border: Border.all(color: const Color(0xFFFF6B9D).withValues(alpha: 0.3)),
            ),
            child: Text('\$${_vibeAmount.toStringAsFixed(2)} hidden ✨',
              style: const TextStyle(fontFamily: 'DMMono', fontSize: 13, color: Color(0xFFFF6B9D), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          Text('Recipient taps to reveal', style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sendVibe,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_selectedSticker?.emoji ?? '✨', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Text('Send Vibe', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ──────────────────────────────────────────────────────────

  Widget _handle(ZendTheme zt) => Center(
    child: Container(width: 36, height: 4,
      decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill))),
  );

  Widget _stepBtn(ZendTheme zt, String label, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 44, height: 44,
      decoration: BoxDecoration(shape: BoxShape.circle, color: onTap != null ? zt.bgPrimary : zt.border.withValues(alpha: 0.3), border: Border.all(color: zt.border)),
      child: Center(child: Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 22, fontWeight: FontWeight.w300, color: onTap != null ? zt.textPrimary : zt.textSecondary))),
    ),
  );

  Widget _primaryBtn(ZendTheme zt, String label, Color color, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: onTap != null ? color : zt.border,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w700)),
    ),
  );

  Widget _keypad(ZendTheme zt) {
    const keys = ['1','2','3','4','5','6','7','8','9','.','0','⌫'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.0,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: keys.map((k) => GestureDetector(
        onTap: () => _onKeypadTap(k),
        child: Container(
          decoration: BoxDecoration(color: zt.bgPrimary, borderRadius: BorderRadius.circular(ZendRadii.md)),
          child: Center(child: Text(k, style: TextStyle(fontFamily: 'DMMono', fontSize: 18, color: k == '⌫' ? zt.accent : zt.textPrimary, fontWeight: FontWeight.w600))),
        ),
      )).toList(),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon; final String label; final Color color; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Expanded(child: GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(ZendRadii.xl), border: Border.all(color: color.withValues(alpha: 0.2), width: 1)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textPrimary)),
      ]),
    )));
  }
}
