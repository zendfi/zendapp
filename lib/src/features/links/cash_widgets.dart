/// Cash: the pieces the Zend sheet, My Links and collecting share.
///
/// * [CashTermsPill]: how many people and how long, in the slot the
///   visibility pill takes for a normal send (cash has no recipient to hide
///   the payment from).
/// * [CashCardView]: the card the sender shares: amount, note, code, QR.
/// * [showCashCodeEntrySheet]: typing a code someone read out or wrote down.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cash_code.dart';
import '../../core/zend_format.dart';
import '../../design/zend_gif.dart' show gifIdFromNote;
import '../../design/zend_link_card.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_money.dart' show isEmojiNote;
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

/// How many people can collect, and for how many days.
class CashTerms {
  const CashTerms({this.uses = 1, this.days = 7});
  final int uses;
  final int days;

  static const maxUses = 100;
  static const dayChoices = [1, 7, 30];

  String get label =>
      '${uses == 1 ? '1 person' : '$uses people'} · '
      '${days == 1 ? '1 day' : '$days days'}';
}

/// Shown where the visibility pill sits while confirming a send.
class CashTermsPill extends StatelessWidget {
  const CashTermsPill({super.key, required this.value, required this.onChanged});

  final CashTerms value;
  final ValueChanged<CashTerms> onChanged;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Semantics(
      button: true,
      label: 'Cash for ${value.label}. Tap to change.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final picked = await _showCashTermsSheet(context, value);
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: zt.bgElevated,
            borderRadius: BorderRadius.circular(ZendRadii.pill),
            border: Border.all(color: zt.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.usersThree, size: 16, color: zt.textPrimary),
              const SizedBox(width: 8),
              Text(
                value.label,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(PhosphorIconsRegular.caretUpDown, size: 14, color: zt.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

Future<CashTerms?> _showCashTermsSheet(BuildContext context, CashTerms start) {
  final zt = ZendTheme.of(context);
  var uses = start.uses;
  var days = start.days;
  TextStyle label() => TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: zt.textSecondary,
  );
  return showZendModalSheet<CashTerms>(
    context: context,
    backgroundColor: zt.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Who can collect it?',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Each person collects once. Whatever is left comes back to you.',
                style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
              ),
              const SizedBox(height: 18),
              Text('People', style: label()),
              const SizedBox(height: 8),
              Row(
                children: [
                  _RoundButton(
                    icon: PhosphorIconsRegular.minus,
                    semantics: 'Fewer people',
                    onTap: uses > 1 ? () => setSheet(() => uses--) : null,
                  ),
                  Expanded(
                    child: Text(
                      uses == 1 ? '1 person' : '$uses people',
                      textAlign: TextAlign.center,
                      style: ZendTextStyles.tabularNumeric.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  _RoundButton(
                    icon: PhosphorIconsRegular.plus,
                    semantics: 'More people',
                    onTap: uses < CashTerms.maxUses ? () => setSheet(() => uses++) : null,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Good for', style: label()),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final d in CashTerms.dayChoices) ...[
                    Expanded(
                      child: _Choice(
                        label: d == 1 ? '1 day' : '$d days',
                        selected: d == days,
                        onTap: () => setSheet(() => days = d),
                      ),
                    ),
                    if (d != CashTerms.dayChoices.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(sheetContext).pop(CashTerms(uses: uses, days: days)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.semantics, this.onTap});
  final IconData icon;
  final String semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: zt.bgSecondary, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: zt.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? zt.accent : zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? zt.onAccent : zt.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── The card ────────────────────────────────────────────────────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _shortDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}

/// What the sender shares: the card (captured as an image), the code, the link.
class CashCardView extends StatefulWidget {
  const CashCardView({
    super.key,
    required this.code,
    required this.amountUsd,
    required this.expiresAt,
    this.uses = 1,
    this.memo,
    this.onDone,
  });

  final CashCode code;

  /// Per person.
  final double amountUsd;
  final int uses;
  final String? memo;
  final DateTime expiresAt;
  final VoidCallback? onDone;

  @override
  State<CashCardView> createState() => _CashCardViewState();
}

class _CashCardViewState extends State<CashCardView> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  String get _shareText =>
      "Here's ${formatMoney(widget.amountUsd)} in Zend cash. "
      'Open ${widget.code.url} or type the code ${widget.code.display} in Zend.';

  Future<Uint8List> _capture() async {
    await Future<void>.delayed(Duration.zero);
    final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('card not on screen');
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('card did not encode');
    return data.buffer.asUint8List();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _capture();
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'zend_cash.png')],
        text: _shareText,
      );
    } catch (_) {
      // No image sharing here (some browsers): the link and code still go.
      await Share.share(_shareText, subject: 'Zend cash for you');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code.display));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _cardKey,
          child: _CashCardFace(
            code: widget.code,
            amountUsd: widget.amountUsd,
            uses: widget.uses,
            memo: widget.memo,
            expiresAt: widget.expiresAt,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Anyone with this code can collect it. Share it only with who it's for.",
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: _sharing ? 'Sharing…' : 'Share card',
          onPressed: _sharing ? null : _share,
        ),
        const SizedBox(height: 10),
        OutlineActionButton(label: 'Copy code', onPressed: _copyCode),
        if (widget.onDone != null) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.onDone,
            child: Text(
              'Done',
              style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w600, color: zt.textPrimary),
            ),
          ),
        ],
      ],
    );
  }
}

class _CashCardFace extends StatelessWidget {
  const _CashCardFace({
    required this.code,
    required this.amountUsd,
    required this.uses,
    required this.memo,
    required this.expiresAt,
  });

  final CashCode code;
  final double amountUsd;
  final int uses;
  final String? memo;
  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final note = (memo == null || gifIdFromNote(memo) != null) ? null : memo!.trim();
    return Material(
      color: zt.bgCard,
      shape: ZendTicketBorder(side: BorderSide(color: zt.border, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(zt.accent, BlendMode.srcIn),
                  child: Image.asset('assets/icons/zend-icon-navbar.png', width: 18, height: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  'Zend cash',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatMoney(amountUsd),
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
            if (uses > 1)
              Text(
                'each, for $uses people',
                style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
              ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                isEmojiNote(note) ? note : '“$note”',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: isEmojiNote(note) ? 28 : 15,
                  color: zt.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            QrImageView(
              data: code.url,
              size: 176,
              backgroundColor: zt.bgCard,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: zt.textPrimary),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              code.display,
              style: ZendTextStyles.tabularNumeric.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Collect at app.usezend.app/cash · good until ${_shortDate(expiresAt)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// My Links: the card again, for cash made on this device.
Future<void> showCashCardSheet(
  BuildContext context, {
  required CashCode code,
  required double amountUsd,
  required DateTime expiresAt,
  int uses = 1,
  String? memo,
}) {
  final zt = ZendTheme.of(context);
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: zt.bgPrimary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
    ),
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZendSheetHandle(),
            const SizedBox(height: 16),
            CashCardView(
              code: code,
              amountUsd: amountUsd,
              uses: uses,
              memo: memo,
              expiresAt: expiresAt,
              onDone: () => Navigator.of(c).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Typing a code ───────────────────────────────────────────────────────────

/// Upper-cases, maps look-alikes and groups as the person types.
class _CashCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // A pasted link: the code is what's after '#'.
    var raw = newValue.text;
    final hash = raw.lastIndexOf('#');
    if (hash >= 0) raw = raw.substring(hash + 1);
    var n = CashCode.normalise(raw);
    if (n.length > kCashCodeLength) n = n.substring(0, kCashCodeLength);
    final text = CashCode.group(n);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// "Have a cash code?" Returns the code once it's complete and passes its
/// check character, or null if closed.
Future<CashCode?> showCashCodeEntrySheet(BuildContext context) {
  return showZendModalSheet<CashCode>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CashCodeEntry(),
  );
}

class _CashCodeEntry extends StatefulWidget {
  const _CashCodeEntry();
  @override
  State<_CashCodeEntry> createState() => _CashCodeEntryState();
}

class _CashCodeEntryState extends State<_CashCodeEntry> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _problem => switch (CashCode.check(_controller.text)) {
    CashCodeProblem.badCharacter => "That isn't a letter or number used in codes.",
    CashCodeProblem.typo => 'That code has a typo. Check it again.',
    CashCodeProblem.tooLong || CashCodeProblem.incomplete || null => null,
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final code = CashCode.tryParse(_controller.text);
    final problem = _problem;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ZendSheetHandle(),
                const SizedBox(height: 18),
                Text(
                  'Have a cash code?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: zt.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Type it the way it was shared with you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: zt.bgSecondary,
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    keyboardType: TextInputType.visiblePassword,
                    inputFormatters: [_CashCodeFormatter()],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (code != null) Navigator.of(context).pop(code);
                    },
                    style: ZendTextStyles.tabularNumeric.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: zt.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'XXXXX-XXXX-XXXX-XXXX',
                      hintStyle: ZendTextStyles.tabularNumeric.copyWith(
                        fontSize: 22,
                        letterSpacing: 1.5,
                        color: zt.textSecondary.withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    ),
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: problem == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            problem,
                            textAlign: TextAlign.center,
                            style: ZendTextStyles.caption.copyWith(color: zt.destructive),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'Collect',
                  onPressed: code == null ? null : () => Navigator.of(context).pop(code),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
