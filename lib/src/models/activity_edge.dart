/// Models for the Phase 2 Activity Relationship Graph read API
/// (`GET /api/zend/activity/edges`, `GET /api/zend/activity/pools/:id/contributors`).
///
/// These are new, additive models — parallel to [TransferHistoryEntry] and
/// friends in `api_models.dart`, not a replacement for them. See
/// `.kiro/specs/activity-relationship-graph/design.md`'s "Activity_Data_Service
/// API contract" section for the JSON shapes this file parses, and
/// `src/activity_data_service.rs` for the authoritative server-side shape.
library;

enum ActivityEdgeKind {
  zendTransfer,
  poolContribution,
  requestFulfillment,
}

ActivityEdgeKind _edgeKindFromString(String raw) {
  switch (raw) {
    case 'zend_transfer':
      return ActivityEdgeKind.zendTransfer;
    case 'pool_contribution':
      return ActivityEdgeKind.poolContribution;
    case 'request_fulfillment':
      return ActivityEdgeKind.requestFulfillment;
    default:
      // Fail open to the most common kind rather than throwing, so an
      // unrecognized future edge_kind value doesn't crash the whole feed —
      // it will simply route through the zend_transfer tap-through handler.
      return ActivityEdgeKind.zendTransfer;
  }
}

String _edgeKindToString(ActivityEdgeKind kind) {
  switch (kind) {
    case ActivityEdgeKind.zendTransfer:
      return 'zend_transfer';
    case ActivityEdgeKind.poolContribution:
      return 'pool_contribution';
    case ActivityEdgeKind.requestFulfillment:
      return 'request_fulfillment';
  }
}

enum VisibilityTier {
  private,
  sharedNetwork,
}

VisibilityTier _tierFromString(String raw) {
  return raw == 'shared_network' ? VisibilityTier.sharedNetwork : VisibilityTier.private;
}

String _tierToString(VisibilityTier tier) {
  return tier == VisibilityTier.sharedNetwork ? 'shared_network' : 'private';
}

/// The other party on an [ActivityEdge] — either a Zend user or a Pool.
class ActivityCounterparty {
  final String kind; // 'user' | 'pool'
  final String id;
  final String? zendtag;
  final String? poolName;
  final String? avatarUrl;

  const ActivityCounterparty({
    required this.kind,
    required this.id,
    this.zendtag,
    this.poolName,
    this.avatarUrl,
  });

  bool get isPool => kind == 'pool';

  factory ActivityCounterparty.fromJson(Map<String, dynamic> json) {
    return ActivityCounterparty(
      kind: json['kind'] as String,
      id: json['id'] as String,
      zendtag: json['zendtag'] as String?,
      poolName: json['pool_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'id': id,
      if (zendtag != null) 'zendtag': zendtag,
      if (poolName != null) 'pool_name': poolName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }
}

/// A single visibility-authorized edge as returned by
/// `GET /api/zend/activity/edges`. Every edge in the response has already
/// been through the server's Authorization_Engine — this model does no
/// filtering of its own.
class ActivityEdge {
  final String edgeId;
  final ActivityEdgeKind edgeKind;
  final ActivityCounterparty counterparty;
  final String? amountUsdc; // null when hidden from this viewer
  final bool amountHidden;
  final String direction; // 'outgoing' | 'incoming'
  final VisibilityTier effectiveTier;
  final bool isDirectParticipant;
  final String? note;
  final DateTime createdAt;

  const ActivityEdge({
    required this.edgeId,
    required this.edgeKind,
    required this.counterparty,
    this.amountUsdc,
    required this.amountHidden,
    required this.direction,
    required this.effectiveTier,
    required this.isDirectParticipant,
    this.note,
    required this.createdAt,
  });

  bool get isOutgoing => direction == 'outgoing';

  factory ActivityEdge.fromJson(Map<String, dynamic> json) {
    return ActivityEdge(
      edgeId: json['edge_id'] as String,
      edgeKind: _edgeKindFromString(json['edge_kind'] as String),
      counterparty:
          ActivityCounterparty.fromJson(json['counterparty'] as Map<String, dynamic>),
      amountUsdc: json['amount_usdc'] as String?,
      amountHidden: json['amount_hidden'] as bool? ?? false,
      direction: json['direction'] as String,
      effectiveTier: _tierFromString(json['effective_tier'] as String),
      isDirectParticipant: json['is_direct_participant'] as bool? ?? true,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'edge_id': edgeId,
      'edge_kind': _edgeKindToString(edgeKind),
      'counterparty': counterparty.toJson(),
      'amount_usdc': amountUsdc,
      'amount_hidden': amountHidden,
      'direction': direction,
      'effective_tier': _tierToString(effectiveTier),
      'is_direct_participant': isDirectParticipant,
      if (note != null) 'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Response envelope for `GET /api/zend/activity/edges`.
class ActivityEdgesResponse {
  final List<ActivityEdge> edges;
  final String? nextCursor;

  const ActivityEdgesResponse({required this.edges, this.nextCursor});

  factory ActivityEdgesResponse.fromJson(Map<String, dynamic> json) {
    return ActivityEdgesResponse(
      edges: (json['edges'] as List<dynamic>? ?? [])
          .map((e) => ActivityEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

/// A single entry in a Pool's rendered contributor list, from
/// `GET /api/zend/activity/pools/:pool_id/contributors`. This is a tagged
/// union mirroring the server's `PoolContributorResponse` enum — either an
/// individually-identified Zend-user Contributor, or the single folded
/// row representing every External_Participant combined.
sealed class PoolContributorEntry {
  const PoolContributorEntry();

  factory PoolContributorEntry.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    switch (kind) {
      case 'external_anonymized':
        return PoolContributorExternalAnonymized(
          aggregateCount: json['aggregate_count'] as int,
          aggregateTotalUsdc: json['aggregate_total_usdc'] as String,
        );
      default: // 'user'
        return PoolContributorUser(
          userId: json['user_id'] as String,
          totalUsdc: json['total_usdc'] as String?,
          amountHidden: json['amount_hidden'] as bool? ?? false,
          zendtag: json['zendtag'] as String?,
        );
    }
  }
}

class PoolContributorUser extends PoolContributorEntry {
  final String userId;
  final String? totalUsdc; // null when hidden from this viewer
  final bool amountHidden;
  final String? zendtag;

  const PoolContributorUser({
    required this.userId,
    this.totalUsdc,
    required this.amountHidden,
    this.zendtag,
  });
}

class PoolContributorExternalAnonymized extends PoolContributorEntry {
  final int aggregateCount;
  final String aggregateTotalUsdc;

  const PoolContributorExternalAnonymized({
    required this.aggregateCount,
    required this.aggregateTotalUsdc,
  });
}

enum PoolVisibilityState {
  private,
  sharedNetwork,
  pendingVisibilityChange,
}

PoolVisibilityState _poolVisibilityStateFromString(String raw) {
  switch (raw) {
    case 'shared_network':
      return PoolVisibilityState.sharedNetwork;
    case 'pending_visibility_change':
      return PoolVisibilityState.pendingVisibilityChange;
    default:
      return PoolVisibilityState.private;
  }
}

/// Response for `GET /api/zend/activity/pools/:pool_id/contributors`.
class PoolContributorsResponse {
  final String poolId;
  final String gatheredAmountUsdc;
  final String targetAmountUsdc;
  final PoolVisibilityState visibilityState;
  final List<PoolContributorEntry> contributors;

  const PoolContributorsResponse({
    required this.poolId,
    required this.gatheredAmountUsdc,
    required this.targetAmountUsdc,
    required this.visibilityState,
    required this.contributors,
  });

  factory PoolContributorsResponse.fromJson(Map<String, dynamic> json) {
    return PoolContributorsResponse(
      poolId: json['pool_id'] as String,
      gatheredAmountUsdc: json['gathered_amount_usdc'] as String,
      targetAmountUsdc: json['target_amount_usdc'] as String,
      visibilityState: _poolVisibilityStateFromString(json['visibility_state'] as String),
      contributors: (json['contributors'] as List<dynamic>? ?? [])
          .map((c) => PoolContributorEntry.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
