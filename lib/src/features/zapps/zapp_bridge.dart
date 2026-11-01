import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_state.dart';
import '../../models/api_exceptions.dart';
import '../../services/appkit_service.dart';
import '../../services/zlink_service.dart';
import 'zapp_confirm_sheet.dart';

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
  });

  final BuildContext context;
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
      case 'interaction.create':
        return _appkit.createInteraction(app.slug, p);
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
      case 'close':
        onClose(p['result']);
        return true;
      default:
        throw ZBridgeError('UNKNOWN_METHOD', 'Unknown method $method');
    }
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

  Future<Object?> _pay(Map<String, dynamic> p) async {
    if (!_can('pay')) {
      throw const ZBridgeError('PERMISSION_DENIED', 'Manifest lacks "pay"');
    }
    final to = _str(p, 'to');
    if (!to.startsWith('@')) {
      throw const ZBridgeError('INVALID_PARAMS', 'to must be an @username');
    }
    final amount = _amount(p);
    final note = p['note'] as String?;
    final reference = p['reference'] as String?;
    // Limits live in core: checked before the user is even asked.
    final check = await _appkit.payCheck(
      app.slug,
      amountUsd: amount,
      to: to,
      reference: reference,
    );
    if (!context.mounted) throw const ZBridgeError('CANCELLED', 'Closed');
    final ok = await confirmZAppMoney(
      context,
      app: app,
      title: 'Send',
      amountLabel: _money2(amount),
      recipient: to,
      note: note,
    );
    if (!ok) throw const ZBridgeError('USER_CANCELLED', 'The user cancelled');
    Future<dynamic> send() => _model.transferService.sendTransfer(
      recipientZendtag: to.substring(1),
      amountUsdc: amount,
      note: note,
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
    // Best effort: the backend verifies its own record before telling the app.
    try {
      await _appkit.payReport(
        app.slug,
        ticket: check,
        transferId: r.transferId as String,
      );
    } catch (_) {}
    return {'paymentId': r.transferId, 'status': r.status};
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
