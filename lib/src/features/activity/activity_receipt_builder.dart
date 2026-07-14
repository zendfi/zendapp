/// Builds the receipt-sheet inputs directly from an [ActivityEdge]'s own
/// carried fields (sender/recipient identity, transaction signature, note,
/// status — added alongside the "@raw-uuid instead of @zendtag" fix), so
/// tapping through to a receipt never depends on cross-referencing a
/// second, separately-fetched list (`recentTransactions`) that may not
/// contain every edge a Shared_Network_Viewer is authorized to see.
///
/// Shared by `threaded_activity_screen.dart` (tapping the most-recent edge
/// on a thread tile) and `thread_detail_screen.dart` (tapping any edge in
/// the per-thread feed).
library;

import '../../core/zend_state.dart';
import '../../models/activity_edge.dart';
import '../../models/api_models.dart';

/// Reconstructs the [TransferHistoryEntry] the receipt sheet needs directly
/// from [edge]. [selfUserId]/[selfZendtag]/[selfDisplayName]/[selfAvatarUrl]
/// are the viewer's own identity, needed because an edge's sender/recipient
/// fields describe the two parties on the edge — which may not include the
/// viewer at all when this edge was surfaced via Shared_Network visibility
/// on someone else's thread (see `getActivityEdgesForUser`/"Your Mutuals").
///
/// Returns null only if the edge is missing the minimum fields required to
/// render a receipt (e.g. a very old cached response predating this fix).
TransferHistoryEntry? entryFromEdge(
  ActivityEdge edge, {
  String? selfUserId,
  String? selfZendtag,
  String? selfDisplayName,
  String? selfAvatarUrl,
}) {
  final isSelfSender = edge.direction == 'outgoing';
  final isExternalEdge = edge.direction == 'external';

  final senderZendtag = isExternalEdge
      ? edge.senderZendtag
      : (isSelfSender ? selfZendtag : edge.counterparty.zendtag);
  final recipientZendtag = isExternalEdge
      ? edge.recipientZendtag
      : (isSelfSender ? edge.counterparty.zendtag : selfZendtag);

  if (edge.transactionSignature == null || senderZendtag == null || recipientZendtag == null) {
    return null;
  }

  final senderAvatarUrl = isExternalEdge ? edge.senderAvatarUrl : (isSelfSender ? selfAvatarUrl : edge.counterparty.avatarUrl);
  final recipientAvatarUrl =
      isExternalEdge ? edge.recipientAvatarUrl : (isSelfSender ? edge.counterparty.avatarUrl : selfAvatarUrl);
  final senderDisplayName =
      isExternalEdge ? edge.senderDisplayName : (isSelfSender ? selfDisplayName : edge.counterparty.displayName);
  final recipientDisplayName =
      isExternalEdge ? edge.recipientDisplayName : (isSelfSender ? edge.counterparty.displayName : selfDisplayName);

  return TransferHistoryEntry(
    id: edge.edgeId,
    senderZendtag: senderZendtag,
    recipientZendtag: recipientZendtag,
    amountUsdc: edge.amountUsdc ?? '0',
    transactionSignature: edge.transactionSignature!,
    note: edge.note,
    status: edge.status ?? 'confirmed',
    createdAt: edge.createdAt,
    senderAvatarUrl: senderAvatarUrl,
    recipientAvatarUrl: recipientAvatarUrl,
    senderDisplayName: senderDisplayName,
    recipientDisplayName: recipientDisplayName,
  );
}

/// Convenience wrapper that pulls the viewer's identity from [model].
TransferHistoryEntry? entryFromEdgeForViewer(ActivityEdge edge, ZendAppModel model) {
  return entryFromEdge(
    edge,
    selfUserId: model.currentUserId,
    selfZendtag: model.currentZendtag,
    selfDisplayName: model.currentDisplayName,
    selfAvatarUrl: model.currentAvatarUrl,
  );
}

/// Builds the [ZendTransaction] wrapper the existing `showTransactionReceipt`
/// sheet expects, given an edge and the entry built from it.
ZendTransaction zendTransactionFromEdge(ActivityEdge edge, TransferHistoryEntry entry, {required String avatarLabel, String? avatarUrl}) {
  return ZendTransaction(
    name: entry.senderZendtag,
    note: edge.note ?? '',
    amount: edge.amountHidden ? 'Hidden' : '${edge.isOutgoing ? '-' : '+'}\$${edge.amountUsdc ?? '0'}',
    time: '',
    avatarLabel: avatarLabel,
    avatarUrl: avatarUrl,
    entry: entry,
    createdAt: edge.createdAt,
  );
}
