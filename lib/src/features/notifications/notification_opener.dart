import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../models/app_notification.dart';
import '../../models/notification_destination.dart';
import '../../models/qr_payment_intent.dart';
import '../../navigation/notification_navigator.dart';
import '../send/qr_payment_sheet.dart';

/// An `app.usezend.app/n/{id}` link (from a notification email) that arrived
/// before the user was signed in and unlocked. app.dart opens it after.
class PendingInboxLink {
  PendingInboxLink._();

  static String? _id;

  static void store(String id) => _id = id;

  static String? consume() {
    final id = _id;
    _id = null;
    return id;
  }
}

/// Opens what an inbox item is about: the same screen a push tap opens, or
/// the pay sheet for a payment request. Marks it read.
Future<void> openInboxItem(
  BuildContext context,
  ZendAppModel model,
  AppNotification n,
) async {
  if (!n.read) unawaited(model.markNotificationRead(n.id));

  if (n.type == 'payment_request') {
    final tag = n.data['requester_zendtag'] as String? ?? '';
    final amount = double.tryParse('${n.data['amount_usdc'] ?? ''}');
    if (tag.isNotEmpty) {
      await showQrPaymentSheet(
        context,
        intent: QrPaymentIntent(zendtag: tag, amountUsdc: amount),
      );
      return;
    }
  }

  await NotificationNavigator.dispatch(
    context,
    NotificationDestination.fromData(n.data),
    model,
  );
}

/// Opens the notification behind an `/n/{id}` link. Only the owner can load
/// it; anything else (someone else's link, an old one) just opens the inbox
/// list's home.
Future<void> openInboxLink(
  BuildContext context,
  ZendAppModel model,
  String id,
) async {
  try {
    final json = await model.walletService.apiClient.getNotification(id);
    if (!context.mounted) return;
    await openInboxItem(context, model, AppNotification.fromJson(json));
  } catch (_) {
    // Not found or offline: nothing to open. The bell still shows it later.
  }
}
