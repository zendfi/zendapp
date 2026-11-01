import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/zlink_service.dart';
import '../deeplink/deep_link_handler.dart';
import 'my_links_screen.dart' show zlinkServiceOf;

/// Holds a Zlink opened before sign-in, so claiming happens right after the
/// normal "Continue with Google". In memory only: the link key must not be
/// written anywhere, and the web OAuth popup does not reload the page.
class PendingZlink {
  PendingZlink._();
  static DeepLinkPayload? _payload;

  static void store(DeepLinkPayload p) => _payload = p;
  static DeepLinkPayload? get peek => _payload;
  static DeepLinkPayload? consume() {
    final p = _payload;
    _payload = null;
    return p;
  }
}

String zlinkAmountLabel(Map<String, dynamic> preview) {
  final kobo = preview['ngn_quote_kobo'] as num?;
  if (kobo != null) return '₦${(kobo / 100).toStringAsFixed(0)}';
  final usd = (preview['amount_usd'] ?? preview['max_amount_usd']) as num?;
  return usd == null ? 'money' : '\$${usd.toStringAsFixed(2)}';
}

/// Opens the right sheet for a Zlink payload. Caller ensures the user is signed in.
Future<void> openZlink(BuildContext context, DeepLinkPayload payload) {
  if (payload.isZlinkGive) {
    return showZendModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ClaimSheet(
        id: payload.zlinkGiveId!,
        keyFragment: payload.zlinkKey ?? '',
      ),
    );
  }
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AskPaySheet(id: payload.zlinkAskId!),
  );
}

/// One line for the welcome screen: "Tolu sent you ₦8,000". Empty otherwise.
class ZlinkWelcomeLine extends StatefulWidget {
  const ZlinkWelcomeLine({super.key});
  @override
  State<ZlinkWelcomeLine> createState() => _ZlinkWelcomeLineState();
}

class _ZlinkWelcomeLineState extends State<ZlinkWelcomeLine> {
  String? _text;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final p = PendingZlink.peek;
    if (p == null || !p.isZlink) return;
    try {
      final service = zlinkServiceOf(context);
      if (p.isZlinkGive) {
        final v = await service.previewGive(p.zlinkGiveId!);
        _text = v['status'] == 'active'
            ? '${v['sender_name']} sent you ${zlinkAmountLabel(v)}'
            : _closedText(v['status'] as String?);
      } else {
        final v = await service.previewAsk(p.zlinkAskId!);
        _text = '${v['payee_name']} is asking for ${zlinkAmountLabel(v)}';
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_text == null) return const SizedBox.shrink();
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        _text!,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: zt.textPrimary,
        ),
      ),
    );
  }
}

String _closedText(String? status) => switch (status) {
  'claimed' => 'This link has already been collected',
  'returned' => 'The sender took this link back',
  _ => 'This link has expired',
};

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: zt.textPrimary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Claims automatically on open: the user already said yes by signing in.
class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.id, required this.keyFragment});
  final String id;
  final String keyFragment;
  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  String _title = 'Collecting your money…';
  String? _body;
  IconData _icon = PhosphorIconsRegular.gift;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
  }

  Future<void> _claim() async {
    final model = ZendScope.of(context);
    final service = zlinkServiceOf(context);
    final key = parseZlinkKey(widget.keyFragment);
    try {
      if (key == null) {
        throw const ZlinkException(
          'This link is incomplete. Ask the sender to share it again.',
        );
      }
      final preview = await service.previewGive(widget.id);
      if (preview['status'] != 'active') {
        throw ZlinkException(_closedText(preview['status'] as String?));
      }
      await service.claim(linkId: widget.id, linkKey: key);
      model.fetchBalance();
      _set(
        PhosphorIconsRegular.checkCircle,
        '${zlinkAmountLabel(preview)} is in your balance',
        'From ${preview['sender_name']}',
      );
    } catch (e) {
      _set(
        PhosphorIconsRegular.warningCircle,
        "Couldn't collect this link",
        e is ZlinkException ? e.message : 'Something went wrong. Try again.',
      );
    }
  }

  void _set(IconData icon, String title, String? body) {
    if (!mounted) return;
    setState(() {
      _icon = icon;
      _title = title;
      _body = body;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    icon: _icon,
    title: _title,
    body: _body,
    action: _done
        ? PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          )
        : const CircularProgressIndicator(),
  );
}

/// Shows what's being asked and pays on confirmation. Paying is a real choice,
/// so unlike claiming it always needs a tap.
class _AskPaySheet extends StatefulWidget {
  const _AskPaySheet({required this.id});
  final String id;
  @override
  State<_AskPaySheet> createState() => _AskPaySheetState();
}

class _AskPaySheetState extends State<_AskPaySheet> {
  Map<String, dynamic>? _preview;
  String? _error;
  bool _paying = false;
  bool _paid = false;
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final v = await zlinkServiceOf(context).previewAsk(widget.id);
        if (mounted) setState(() => _preview = v);
      } catch (_) {
        if (mounted) setState(() => _error = "This link doesn't exist");
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final fixed = _preview!['amount_usd'] as num?;
    final amount = fixed?.toDouble() ?? double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    final model = ZendScope.of(context);
    final service = zlinkServiceOf(context);
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      await service.payAsk(widget.id, amountUsd: amount);
      model.fetchBalance();
      if (mounted) setState(() => _paid = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ZlinkException
              ? e.message
              : "Payment didn't go through. Try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _preview;
    if (v == null) {
      return _SheetFrame(
        icon: PhosphorIconsRegular.handCoins,
        title: _error ?? 'Loading…',
        action: _error == null ? const CircularProgressIndicator() : null,
      );
    }
    if (_paid) {
      return _SheetFrame(
        icon: PhosphorIconsRegular.checkCircle,
        title: 'Paid ${v['payee_name']}',
        action: PrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      );
    }
    if (v['status'] != 'active') {
      return const _SheetFrame(
        icon: PhosphorIconsRegular.warningCircle,
        title: 'This link is no longer collecting',
      );
    }
    final fixed = v['amount_usd'] != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _SheetFrame(
        icon: PhosphorIconsRegular.handCoins,
        title: fixed
            ? 'Pay ${v['payee_name']} ${zlinkAmountLabel(v)}'
            : 'Pay ${v['payee_name']}',
        body: [
          v['memo'] as String?,
          _error,
        ].whereType<String>().join('\n').ifEmpty,
        action: Column(
          children: [
            if (!fixed)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: 'Amount'),
                ),
              ),
            PrimaryButton(
              label: 'Pay',
              isLoading: _paying,
              onPressed: _paying ? null : _pay,
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
