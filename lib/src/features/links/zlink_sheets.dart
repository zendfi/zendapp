import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/zend_format.dart';
import '../../design/zend_keypad.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_motion_widgets.dart' show showReceiveMoment;
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart' show zendRoute;
import '../../services/dev_return_redirect_service.dart';
import '../../services/zlink_service.dart';
import '../deeplink/deep_link_handler.dart';
import '../dm/dm_thread_screen.dart';
import '../onboarding/zendtag_prompt_sheet.dart' show showZendtagPromptSheet;
import '../wallet/add_cash_sheet.dart' show showAddCashSheet;
import 'my_links_screen.dart' show zlinkServiceOf;

part 'ask_bank_pay.dart';

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

/// Whether to offer "Message" after collecting or paying a link.
///
/// [userId] and [fromApp] come from the claim or pay response (the previews
/// never carry user ids). Hidden for links made through a ZApp, where the
/// person may not know who made the link, and when the server only knew the
/// other side as "Someone" (no name, or a closed account).
bool zlinkCanMessage({
  required Object? userId,
  required Object? fromApp,
  required Object? name,
}) =>
    userId is String &&
    userId.isNotEmpty &&
    fromApp != true &&
    name is String &&
    name.trim().isNotEmpty &&
    name != 'Someone';

/// Opens a chat with the other person on a link. Values are captured before
/// any sheet closes, since the caller's context may be gone by then. Nothing
/// is sent: the chat opens empty for the person to write in.
Future<void> _openChatWith({
  required ZendAppModel model,
  required NavigatorState navigator,
  required ScaffoldMessengerState? messenger,
  required String userId,
}) async {
  try {
    final room = await model.dmService.getOrCreateRoom(userId);
    if (!navigator.mounted) return;
    await navigator.push(
      zendRoute<void>(
        page: DmThreadScreen(
          roomId: room.roomId,
          counterparty: room.counterparty,
        ),
      ),
    );
  } catch (_) {
    // Blocked either way, a closed account, or the network.
    messenger?.showSnackBar(
      const SnackBar(content: Text("That didn't go through. Try again.")),
    );
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
  return _openAsk(context, payload.zlinkAskId!);
}

Future<void> _openAsk(BuildContext context, String id) async {
  final model = ZendScope.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  await showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AskPaySheet(id: id),
  );
  // A new account that arrived through this link: the username offer was
  // held back so paying came first. Offer it now that the sheet is closed,
  // once, and only if they still have no username.
  if (!model.zendtagOfferAfterAsk) return;
  model.zendtagOfferAfterAsk = false;
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (!navigator.mounted || !model.zendtagIsPlaceholder) return;
  await showZendtagPromptSheet(navigator.context);
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
  // The arrival is felt and seen before the collect finishes underneath; if
  // it doesn't land, the balance steps back and the sheet below explains.
  if (amount > 0 && navigator.mounted) {
    unawaited(
      showReceiveMoment(
        navigator.context,
        amount: amount,
        from: (preview['sender_name'] as String?) ?? 'Someone',
        note: preview['memo'] as String?,
        viaLink: true,
      ),
    );
  }
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
      final claimed = await service.claim(linkId: id, linkKey: key);
      if (arriving != null) {
        unawaited(model.finishArriving(arriving, landed: true));
      } else {
        model.fetchBalance();
      }
      // Now that it has landed, offer a chat with the sender. Same line as
      // before, with a Message action added.
      final senderId = claimed['sender_user_id'];
      if (zlinkCanMessage(
        userId: senderId,
        fromApp: claimed['from_app'],
        name: preview['sender_name'],
      )) {
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              '${preview['sender_name']} sent you ${zlinkAmountLabel(preview)}',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Message',
              onPressed: () => _openChatWith(
                model: model,
                navigator: navigator,
                messenger: messenger,
                userId: senderId as String,
              ),
            ),
          ),
        );
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

  /// Set from the pay response when "Message" should show on the paid sheet.
  String? _messageUserId;
  final _amount = TextEditingController();

  /// Naira when a rate is known as the sheet opens, else dollars.
  final AmountEntry _entry = AmountEntry.current();

  /// Paying by bank transfer instead of from the balance.
  bool _byBank = false;

  /// Whether the balance could pay this link, so the bank sheet offers it.
  bool _balanceCovers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final model = ZendScope.of(context);
      try {
        final v = await zlinkServiceOf(context).previewAsk(widget.id);
        // Someone new to Zend has nothing to pay from yet, so go straight to
        // paying by bank. Only once the balance is actually known: a zero
        // that hasn't loaded yet isn't an empty Zend.
        // Right after creating an account the first reads can fail while the
        // session settles, so give it a few tries.
        for (final wait in const [0, 2, 4]) {
          if (model.balanceLoaded) break;
          if (wait > 0) await Future<void>.delayed(Duration(seconds: wait));
          await model.fetchBalance().timeout(
            const Duration(seconds: 6),
            onTimeout: () {},
          );
        }
        final known = model.balanceLoaded;
        final have = model.spendableBalance;
        final ask = (v['amount_usd'] as num?)?.toDouble();
        final covers = have > 0 && (ask == null || have >= ask);
        if (mounted) {
          setState(() {
            _preview = v;
            // Still unknown: offer paying from the balance too, in case
            // there is money there.
            _balanceCovers = covers || !known;
            // Unknown means most likely a brand-new account, which can only
            // pay by bank, so that's the safer default.
            _byBank = !covers;
          });
        }
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

  /// Closes this sheet and opens the chat. Everything the chat needs is
  /// captured first, because this sheet's context goes away on pop.
  void _message(String userId) {
    final model = ZendScope.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    unawaited(
      _openChatWith(
        model: model,
        navigator: navigator,
        messenger: messenger,
        userId: userId,
      ),
    );
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
      // A developer checkout ("Pay with Zend") sends the payer back to the
      // site, so there's no chat to offer.
      final payeeId = paid['payee_user_id'];
      final offerChat =
          paid['dev_request_id'] == null &&
          zlinkCanMessage(
            userId: payeeId,
            fromApp: paid['from_app'],
            name: _preview!['payee_name'],
          );
      if (mounted) {
        setState(() {
          _paid = true;
          _messageUserId = offerChat ? payeeId as String : null;
        });
      }
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
      final done = PrimaryButton(
        label: 'Done',
        onPressed: () => Navigator.of(context).pop(),
      );
      final messageUserId = _messageUserId;
      return _SheetFrame(
        icon: PhosphorIconsRegular.checkCircle,
        title: 'Paid ${v['payee_name']}',
        action: messageUserId == null
            ? done
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlineActionButton(
                    label: 'Message ${v['payee_name']}',
                    onPressed: () => _message(messageUserId),
                  ),
                  const SizedBox(height: 12),
                  done,
                ],
              ),
      );
    }
    if (v['status'] != 'active') {
      return const _SheetFrame(
        icon: PhosphorIconsRegular.warningCircle,
        title: 'This link is no longer collecting',
      );
    }
    if (_byBank) {
      return _AskBankPay(
        id: widget.id,
        preview: v,
        canPayFromBalance: _balanceCovers,
        onUseBalance: () => setState(() => _byBank = false),
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
            TextButton(
              onPressed: _paying ? null : () => setState(() => _byBank = true),
              child: const Text('Pay by bank transfer instead'),
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
