import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/zend_format.dart';
import '../../design/zend_keypad.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_money.dart' show ZendFeel;
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/dev_return_redirect_service.dart';
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
  if (kobo != null) return formatNaira((kobo / 100).roundToDouble());
  final usd = (preview['amount_usd'] ?? preview['max_amount_usd']) as num?;
  return usd == null ? 'money' : formatMoney(usd.toDouble());
}

/// Opens the right sheet for a Zlink payload. Caller ensures the user is signed in.
Future<void> openZlink(BuildContext context, DeepLinkPayload payload) {
  if (payload.isZlinkGive) {
    return _receiveQuietly(
      context,
      payload.zlinkGiveId!,
      payload.zlinkKey ?? '',
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
  String? _sub;

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
        final active = v['status'] == 'active';
        _text = active
            ? '${v['sender_name']} sent you ${zlinkAmountLabel(v)}'
            : _closedText(v['status'] as String?);
        _sub = active ? "It'll be in your balance as soon as you're in." : null;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _text!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          if (_sub != null) ...[
            const SizedBox(height: 4),
            Text(
              _sub!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _closedText(String? status) => switch (status) {
  'claimed' => 'This money has already been received',
  'returned' => 'The sender took this back',
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

/// Money someone sent by link arrives like any other money: no sheet, no
/// spinner, nothing to tap. It moves into the balance in the background and a
/// quiet "Tolu sent you ₦8,000" appears once it's there, the way a normal
/// payment does. Only a link that can't be used gets a screen of its own.
Future<void> _receiveQuietly(
  BuildContext context,
  String id,
  String keyFragment,
) async {
  final model = ZendScope.of(context);
  final service = zlinkServiceOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  void explain(String title, String body) {
    if (!navigator.mounted) return;
    showZendModalSheet<void>(
      context: navigator.context,
      builder: (c) => _SheetFrame(
        icon: PhosphorIconsRegular.info,
        title: title,
        body: body,
        action: PrimaryButton(
          label: 'OK',
          onPressed: () => Navigator.of(c).pop(),
        ),
      ),
    );
  }

  final key = parseZlinkKey(keyFragment);
  if (key == null) {
    explain(
      'This link is incomplete',
      'Ask the person who sent it to share it again.',
    );
    return;
  }
  // The count-up starts from the real balance, so load it alongside the link
  // (right after sign-in it may not be loaded yet).
  final balanceReady = model.fetchBalance();
  Map<String, dynamic> preview;
  try {
    preview = await service.previewGive(id);
  } catch (_) {
    explain("We couldn't open this link", 'Open it again in a moment.');
    return;
  }
  if (preview['status'] != 'active') {
    explain(_closedText(preview['status'] as String?), _closedBody(preview));
    return;
  }

  // The money shows in the balance now and counts up into place, like any
  // money arriving; moving it in happens underneath. The display can't be
  // spent from until it lands (see ZendAppModel.beginArriving).
  await balanceReady;
  final amount = (preview['amount_usd'] as num?)?.toDouble() ?? 0;
  final arriving = amount > 0 ? model.beginArriving(amount) : null;
  ZendFeel.received();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        '${preview['sender_name']} sent you ${zlinkAmountLabel(preview)}',
      ),
    ),
  );

  // A brief network or sponsor hiccup shouldn't become a message: try a few
  // times quietly before saying anything.
  Object? last;
  for (final wait in const [0, 2, 5]) {
    if (wait > 0) await Future<void>.delayed(Duration(seconds: wait));
    try {
      await service.claim(linkId: id, linkKey: key);
      if (arriving != null) {
        unawaited(model.finishArriving(arriving, landed: true));
      } else {
        model.fetchBalance();
      }
      return;
    } on ApiException catch (e) {
      last = e;
      if (e.errorCode == 'OWN_LINK') {
        if (arriving != null) {
          unawaited(model.finishArriving(arriving, landed: false));
        }
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'This is your own link. You can take it back from My Links.',
            ),
          ),
        );
        return;
      }
      // Only retry what can change on its own.
      if (e.retryable != true && e.statusCode < 500) break;
    } on ZlinkException catch (e) {
      last = e;
      break; // the app refused to sign: retrying won't help
    } catch (e) {
      last = e;
    }
  }
  // It didn't land: take it back off the balance and say so plainly.
  if (arriving != null) {
    unawaited(model.finishArriving(arriving, landed: false));
  }
  messenger?.hideCurrentSnackBar();
  explain(
    "That didn't go through",
    last is ZlinkException
        ? last.message
        : 'The money is still waiting for you. Open the link again in a moment.',
  );
}

String _closedBody(Map<String, dynamic> preview) {
  final name = preview['sender_name'] as String? ?? 'the sender';
  return switch (preview['status']) {
    'claimed' => 'If it was meant for you, ask $name about it.',
    'returned' => 'Ask $name to send it again if it was meant for you.',
    _ => 'Links last a few days. The money went back to $name.',
  };
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

  /// Naira when a rate is known as the sheet opens, else dollars.
  final AmountEntry _entry = AmountEntry.current();

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
    final amount = fixed?.toDouble() ?? _entry.usd(_amount.text);
    if (amount <= 0) {
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
      final paid = await service.payAsk(widget.id, amountUsd: amount);
      model.fetchBalance();
      // "Pay with Zend" from a developer's site: send the payer back there.
      final token = paid['return_token'] as String?;
      final redirect = paid['redirect_url'] as String?;
      final devId = paid['dev_request_id'] as String?;
      if (token != null && redirect != null && devId != null) {
        await DevReturnRedirectService.redirectAndReportOutcome(
          apiClient: model.walletService.apiClient,
          requestId: devId,
          redirectUrl: redirect,
          token: token,
          platform: defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        );
      }
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
                  inputFormatters: [AmountInputFormatter(naira: _entry.naira)],
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !_entry.naira,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Amount',
                    prefixText: _entry.symbol,
                  ),
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
