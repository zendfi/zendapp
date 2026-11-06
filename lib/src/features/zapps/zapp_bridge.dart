import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_format.dart' show formatNaira;
import '../../core/zend_state.dart';
import '../../models/api_exceptions.dart';
import '../../services/appkit_service.dart';
import '../../services/sui_transaction_verifier.dart';
import '../../services/prize_service.dart';
import '../../services/zlink_service.dart';
import 'zapp_confirm_sheet.dart';
import 'zapp_live.dart';
import 'zapp_people_picker.dart';

/// Typed bridge error. `code` is for the developer; it is never shown to users.
class ZBridgeError implements Exception {
  const ZBridgeError(this.code, this.message);
  final String code;
  final String message;
}

/// Transport-neutral handler for the ZendAppKit bridge (JSON-RPC 2.0-like):
///   request  {zend:1, id, method, params}
///   response {zend:1, id, result} | {zend:1, id, error:{code, message}}
///
/// The app id comes from [app] (the registry entry this sheet was opened
/// for), never from the page. Hosts (WebView, iframe) must check the message
/// origin against [ZAppDescriptor.allows] before calling [handle].
class ZAppBridge {
  ZAppBridge({
    required this.context,
    required this.app,
    required this.session,
    required this.onClose,
    this.live,
    Map<String, String>? picks,
  }) : picks = picks ?? {};

  final BuildContext context;

  /// Held by the ZApp screen (not the bridge, which is rebuilt with it) so
  /// rooms survive rebuilds and close when the app closes.
  final ZAppLiveRooms? live;

  /// Opaque `pick_…` tokens handed to the page by `people.pick`, mapped to the
  /// chosen person's user id. The page passes tokens back as interaction
  /// participants; it never sees user ids. Held by the ZApp screen.
  final Map<String, String> picks;
  final ZAppDescriptor app;

  /// From `/session` or `/connect`: app_session token, scopes, app_user_id.
  Map<String, dynamic> session;
  final void Function(Object? result) onClose;

  bool _busy = false;

  ZendAppModel get _model => ZendScope.of(context);
  AppKitService get _appkit => AppKitService(_model.walletService.apiClient);
  ZlinkService get _zlinks => ZlinkService(
    api: _model.walletService.apiClient,
    zkLogin: _model.zkLoginService,
  );

  PrizeService get _prizes => PrizeService(
    api: _model.walletService.apiClient,
    zkLogin: _model.zkLoginService,
  );

  static String _duration(int secs) => secs >= 86400
      ? '${(secs / 86400).round()} days'
      : secs >= 3600
      ? '${(secs / 3600).round()} hours'
      : '${(secs / 60).round()} minutes';

  Future<Object?> _prizeCreate(Map<String, dynamic> p) async {
    if (!_can('prize')) {
      throw const ZBridgeError('PERMISSION_DENIED', 'Manifest lacks "prize"');
    }
    final amount = _amount(p, min: 1);
    final joinIn = (p['joinInSecs'] as num?)?.toInt() ?? 0;
    final resolveIn = (p['resolveInSecs'] as num?)?.toInt() ?? 0;
    final maxPlayers = (p['maxPlayers'] as num?)?.toInt() ?? 0;
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Put up a prize of',
      amountLabel: _money2(amount),
      note:
          'Up to $maxPlayers people can join for ${_duration(joinIn)}. '
          '${app.name} decides the winners. If there is no result in ${_duration(resolveIn)}, '
          'or you cancel during the short wait after results, it all comes back to you. '
          'Held safely until the rules say who gets it.',
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    final r = await _prizes.create(
      app: app.slug,
      amountUsd: amount,
      joinInSecs: joinIn,
      resolveInSecs: resolveIn,
      maxPlayers: maxPlayers,
      disputeSecs: (p['disputeSecs'] as num?)?.toInt(),
      reference: p['reference'] as String?,
      interactionId: p['interactionId'] as String?,
    );
    _model.fetchBalance();
    return r;
  }

  Future<Object?> _prizeJoin(Map<String, dynamic> p) async {
    final id = _str(p, 'id');
    final prize = await _prizes.get(id);
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Join for a chance to win',
      amountLabel: _money2((prize['pot_usd'] as num).toDouble()),
      note: "It's free to join. ${app.name} decides the winners.",
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    return _prizes.join(id);
  }

  Future<Object?> _prizeCancel(Map<String, dynamic> p) async {
    final id = _str(p, 'id');
    final prize = await _prizes.get(id);
    if (prize['is_host'] != true) {
      throw const ZBridgeError('NOT_HOST', 'Only the host can cancel');
    }
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Cancel the prize and take back',
      amountLabel: _money2((prize['pot_usd'] as num).toDouble()),
      note: 'Nobody gets paid. All of it comes back to you.',
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    final r = await _prizes.veto(id);
    _model.fetchBalance();
    return r;
  }

  bool _can(String permission) => app.permissions.contains(permission);

  /// Parses one raw message and returns the raw response, or null to ignore.
  Future<String?> handleRaw(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
    if (msg['zend'] != 1 || msg['method'] is! String) return null;
    final id = msg['id'];
    try {
      final result = await handle(
        msg['method'] as String,
        Map<String, dynamic>.from((msg['params'] as Map?) ?? const {}),
      );
      return jsonEncode({'zend': 1, 'id': id, 'result': result});
    } on ZBridgeError catch (e) {
      return jsonEncode({
        'zend': 1,
        'id': id,
        'error': {'code': e.code, 'message': e.message},
      });
    } on ApiException catch (e) {
      return jsonEncode({
        'zend': 1,
        'id': id,
        'error': {'code': e.errorCode, 'message': e.userMessage},
      });
    } catch (e) {
      return jsonEncode({
        'zend': 1,
        'id': id,
        'error': {'code': 'INTERNAL', 'message': '$e'},
      });
    }
  }

  Future<Object?> handle(String method, Map<String, dynamic> p) async {
    switch (method) {
      case 'identity.get':
        return {
          'appUserId': session['app_user_id'],
          'username': _model.zendtagIsPlaceholder
              ? null
              : _model.currentZendtag,
          'name': _model.currentDisplayName,
          'scopes': session['scopes'],
          // Short-lived; the app's server exchanges it at /apps/token/verify.
          'appSession': session['app_session'],
        };
      case 'pay':
        return _money(() => _pay(p));
      case 'request':
        return _money(() => _request(p));
      case 'createLink':
        return _money(() => _createLink(p));
      case 'people.pick':
        return _pickPeople(p);
      case 'interaction.create':
        return _appkit.createInteraction(app.slug, _withPicks(p));
      case 'interaction.get':
        return _appkit.getInteraction(_str(p, 'id'));
      case 'interaction.update':
        final id = _str(p, 'id');
        return _appkit.updateInteraction(id, Map.of(p)..remove('id'));
      case 'card.post':
        if (!_can('post_card')) {
          throw const ZBridgeError(
            'PERMISSION_DENIED',
            'Manifest lacks "post_card"',
          );
        }
        return _appkit.postCard(p);
      case 'attest':
        if (!_can('attest')) {
          throw const ZBridgeError(
            'PERMISSION_DENIED',
            'Manifest lacks "attest"',
          );
        }
        return _model.walletService.apiClient.appkit('POST', '/apps/attest', {
          'app': app.slug,
          'label': _str(p, 'label'),
          'data_hash': _str(p, 'dataHash'),
          'interaction_id': ?(p['interactionId'] as String?),
        });
      case 'prize.get':
        return _prizes.get(_str(p, 'id'));
      case 'prize.create':
        return _money(() => _prizeCreate(p));
      case 'prize.join':
        return _money(() => _prizeJoin(p));
      case 'prize.cancel':
        return _money(() => _prizeCancel(p));
      case 'report':
        return _model.walletService.apiClient
            .appkit('POST', '/apps/by-slug/${app.slug}/report', {
              'reason': _str(p, 'reason'),
              'detail': ?(p['detail'] as String?),
              'interaction_id': ?(p['interactionId'] as String?),
              'prize_id': ?(p['prizeId'] as String?),
            });
      case 'live.join':
      case 'live.send':
      case 'live.leave':
        return _liveCall(method, p);
      case 'close':
        onClose(p['result']);
        return true;
      default:
        throw ZBridgeError('UNKNOWN_METHOD', 'Unknown method $method');
    }
  }

  Future<Object?> _pickPeople(Map<String, dynamic> p) async {
    final max = ((p['max'] as num?)?.toInt() ?? 1).clamp(1, 50);
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final chosen = await showZAppPeoplePicker(
      context,
      appName: app.name,
      title: p['title'] as String?,
      max: max,
    );
    if (chosen.isEmpty) return <Object>[];
    final r = await _model.walletService.apiClient.appkit(
      'POST',
      '/apps/people/handles',
      {
        'app': app.slug,
        'user_ids': [for (final c in chosen) c.userId],
      },
    );
    final out = <Map<String, dynamic>>[];
    for (final person in (r['people'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(person as Map);
      final token = 'pick_${_randomToken()}';
      picks[token] = m['user_id'] as String;
      out.add({
        'appUserId': m['app_user_id'],
        'name': m['name'],
        'username': m['username'],
        'avatar': m['avatar'],
        'pick': token,
      });
    }
    return out;
  }

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Turns `pick_…` participants into the `chat:<id>` form Zend resolves for
  /// people the user chats with. Unknown tokens are refused.
  Map<String, dynamic> _withPicks(Map<String, dynamic> p) {
    final raw = p['participants'];
    if (raw is! List) return p;
    final mapped = <Object?>[];
    for (final x in raw) {
      if (x is String && x.startsWith('pick_')) {
        final id = picks[x];
        if (id == null) {
          throw const ZBridgeError('INVALID_PARAMS', 'Unknown pick token');
        }
        mapped.add('chat:$id');
      } else if (x is String && x.startsWith('chat:')) {
        // Only Zend itself writes this form.
        throw const ZBridgeError('INVALID_PARAMS', 'Invalid participant');
      } else {
        mapped.add(x);
      }
    }
    return {...p, 'participants': mapped};
  }

  Future<Object?> _liveCall(String method, Map<String, dynamic> p) async {
    final rooms = live;
    if (rooms == null) {
      throw const ZBridgeError('UNAVAILABLE', 'Live rooms are not available');
    }
    final id = _str(p, 'interactionId');
    try {
      switch (method) {
        case 'live.join':
          await rooms.join(id);
        case 'live.send':
          final data = p['data'];
          if (jsonEncode(data).length > 8 * 1024) {
            throw const ZBridgeError(
              'LIVE_FRAME_TOO_LARGE',
              'Messages must be at most 8 KB',
            );
          }
          rooms.send(id, data);
        default:
          rooms.leave(id);
      }
    } on StateError catch (e) {
      throw ZBridgeError(e.message, 'Live room: ${e.message}');
    }
    return true;
  }

  /// One money sheet at a time, so a page can't stack prompts.
  Future<Object?> _money(Future<Object?> Function() run) async {
    if (_busy) throw const ZBridgeError('BUSY', 'Another request is open');
    _busy = true;
    try {
      return await run();
    } finally {
      _busy = false;
    }
  }

  static String _str(Map<String, dynamic> p, String k) {
    final v = p[k];
    if (v is String && v.isNotEmpty) return v;
    throw ZBridgeError('INVALID_PARAMS', '$k is required');
  }

  static double _amount(Map<String, dynamic> p, {double min = 0.01}) {
    final v = p['amount'];
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    if (d == null || !d.isFinite || d < min || d > 10000) {
      throw ZBridgeError(
        'INVALID_AMOUNT',
        'amount must be between $min and 10000',
      );
    }
    return d;
  }

  static String _money2(double usd) => '\$${usd.toStringAsFixed(2)}';

  /// `price: { ngn: 2000 }` from the page, or null when it gave `amount`.
  static double? _priceNgn(Map<String, dynamic> p) {
    final price = p['price'];
    if (price == null) return null;
    final v = price is Map ? price['ngn'] : null;
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    if (d == null || !d.isFinite || d < 1 || d > 10000000) {
      throw const ZBridgeError(
        'INVALID_AMOUNT',
        'price.ngn must be between 1 and 10000000',
      );
    }
    return d;
  }

  Future<Object?> _pay(Map<String, dynamic> p) async {
    if (!_can('pay')) {
      throw const ZBridgeError('PERMISSION_DENIED', 'Manifest lacks "pay"');
    }
    final to = _str(p, 'to');
    if (!to.startsWith('@')) {
      throw const ZBridgeError('INVALID_PARAMS', 'to must be an @username');
    }
    if (p['splits'] is List && (p['splits'] as List).isNotEmpty) {
      return _paySplit(p, to);
    }
    // A price in Naira (`price: { ngn }`) or an amount in dollars (`amount`).
    final priceNgn = _priceNgn(p);
    final note = p['note'] as String?;
    final reference = p['reference'] as String?;
    // Limits live in core: checked before the user is even asked. Zend also
    // converts a Naira price here, so the amount sent is the one it checked.
    final checked = await _appkit.payCheck(
      app.slug,
      amountUsd: priceNgn == null ? _amount(p) : null,
      priceNgn: priceNgn,
      to: to,
      reference: reference,
    );
    final check = checked.ticket;
    final amount = checked.amountUsd;
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Send',
      amountLabel: checked.priceNgn != null
          ? formatNaira(checked.priceNgn!)
          : _money2(amount),
      recipient: to,
      note: note,
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    Future<dynamic> send() => _model.transferService.sendTransfer(
      recipientZendtag: to.substring(1),
      amountUsdc: amount,
      note: note,
      // Zend records the payment for the app at submit, even if this app closes after.
      appTicket: check,
    );
    dynamic r;
    try {
      r = await send();
    } on ApiException catch (e) {
      if (e.errorCode != 'STEP_UP_REQUIRED') rethrow;
      await _model.zkLoginService.satisfyStepUp();
      r = await send();
    }
    _model.fetchBalance();
    // Older backends record only on report. Newer ones already recorded it at submit, so
    // this is a no-op there. Best effort either way.
    try {
      await _appkit.payReport(
        app.slug,
        ticket: check,
        transferId: r.transferId as String,
      );
    } catch (_) {}
    return {'paymentId': r.transferId, 'status': r.status};
  }

  /// `pay` with `splits`: one transaction pays the recipient and the others
  /// (for example the app's share). Every part is shown before confirming,
  /// and the prepared transaction is checked against exactly those parts.
  Future<Object?> _paySplit(Map<String, dynamic> p, String to) async {
    final priceNgn = _priceNgn(p);
    final api = _model.walletService.apiClient;
    final checked = await api.appkit(
      'POST',
      '/apps/by-slug/${app.slug}/split/check',
      {
        'to': to,
        if (priceNgn == null) 'amount_usd': _amount(p),
        'price_ngn': ?priceNgn,
        'splits': [
          for (final s in (p['splits'] as List))
            {
              'to': (s as Map)['to'],
              'percent': ?s['percent'],
              'amount_usd': ?s['amount'],
            },
        ],
        'reference': ?(p['reference'] as String?),
      },
    );
    final ticket = checked['ticket'] as String;
    final total = (checked['amount_usd'] as num).toDouble();
    final totalNgn = (checked['price_ngn'] as num?)?.toDouble();
    final parts = (checked['parts'] as List).cast<Map>();
    String label(Map part) {
      final ngn = (part['price_ngn'] as num?)?.toDouble();
      return ngn != null
          ? formatNaira(ngn)
          : _money2((part['amount_usd'] as num).toDouble());
    }

    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Send',
      amountLabel: totalNgn != null ? formatNaira(totalNgn) : _money2(total),
      note: p['note'] as String?,
      parts: [for (final part in parts) (part['label'] as String, label(part))],
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');

    Future<Map<String, dynamic>> prepare() => api.appkit(
      'POST',
      '/apps/by-slug/${app.slug}/split/prepare',
      {'ticket': ticket},
    );
    Map<String, dynamic> prepared;
    try {
      prepared = await prepare();
    } on ApiException catch (e) {
      if (e.errorCode != 'STEP_UP_REQUIRED') rethrow;
      await _model.zkLoginService.satisfyStepUp();
      prepared = await prepare();
    }
    final tx = prepared['transaction_data_bcs'] as String;
    final preparedParts = (prepared['parts'] as List).cast<Map>();
    // The amounts must be the ones just shown, in the same order.
    if (preparedParts.length != parts.length) {
      throw const ZBridgeError(
        'SAFETY_STOP',
        "We stopped this because something didn't look right. Your money hasn't moved.",
      );
    }
    try {
      verifyGaslessUsdcSplit(
        transactionDataBcsBase64: tx,
        senderAddress: prepared['sender'] as String,
        parts: [
          for (var i = 0; i < parts.length; i++)
            SuiSplitPart(
              address: preparedParts[i]['address'] as String,
              amountBaseUnits: BigInt.from(
                ((parts[i]['amount_usd'] as num) * 1000000).round(),
              ),
            ),
        ],
      );
    } on Exception {
      throw const ZBridgeError(
        'SAFETY_STOP',
        "We stopped this because something didn't look right. Your money hasn't moved.",
      );
    }
    final signature = await _model.zkLoginService.signPreparedTransaction(
      transactionDataBcsBase64: tx,
    );
    final r = await api.appkit(
      'POST',
      '/apps/by-slug/${app.slug}/split/submit',
      {'ticket': ticket, 'transaction_data_bcs': tx, 'signature': signature},
    );
    _model.fetchBalance();
    return {'paymentId': r['payment_id'], 'status': r['status']};
  }

  Future<Object?> _request(Map<String, dynamic> p) async {
    if (!_can('request_payment')) {
      throw const ZBridgeError(
        'PERMISSION_DENIED',
        'Manifest lacks "request_payment"',
      );
    }
    final amount = p['amount'] == null ? null : _amount(p);
    final note = p['note'] as String?;
    final maxPayments = (p['maxPayments'] as num?)?.toInt();
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Ask for',
      amountLabel: amount == null ? 'Any amount' : _money2(amount),
      note: note,
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    final url = await _zlinks.createAskLink(
      amountUsd: amount,
      maxPayments: maxPayments,
      memo: note,
      app: app.slug,
      reference: p['reference'] as String?,
    );
    // Ask links carry no secret, so the app may have the URL.
    return {'id': Uri.parse(url).pathSegments.last, 'url': url};
  }

  Future<Object?> _createLink(Map<String, dynamic> p) async {
    if (!_can('create_link')) {
      throw const ZBridgeError(
        'PERMISSION_DENIED',
        'Manifest lacks "create_link"',
      );
    }
    final amount = _amount(p, min: 1);
    final uses = ((p['uses'] as num?) ?? 1).toInt().clamp(1, 100);
    final note = p['note'] as String?;
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: uses > 1
          ? 'Make a money link for $uses people, each'
          : 'Make a money link for',
      amountLabel: _money2(amount),
      note: note,
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    final link = await _zlinks.createGiveLink(
      amountUsd: amount,
      uses: uses,
      memo: note,
      app: app.slug,
      reference: p['reference'] as String?,
    );
    _model.fetchBalance();
    // A money link works like cash: Zend shares it, the app only gets the id.
    await Share.share('Here\'s money for you on Zend: ${link.url}');
    return {'id': link.id, 'status': 'active'};
  }
}
