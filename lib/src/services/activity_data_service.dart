import 'api_client.dart';
import '../models/activity_edge.dart';

/// A new, separate service for the Phase 2/3 Activity Relationship Graph
/// read API — parallel to [ApiClient]'s existing `getTransferHistory()`,
/// not a wrapper around it. Per design.md's "parallel path, not extend/wrap
/// fetchHistory()" decision: `ZendAppModel.fetchHistory()` and everything it
/// powers (home screen, search screen, receipt sheet) stay completely
/// untouched by this service (Req 22.4 backward compatibility).
///
/// Delegates to the two new `ApiClient` methods (`getActivityEdges`,
/// `getPoolContributors`), which follow the exact `Dio`-based request
/// pattern already used throughout `api_client.dart`. This class exists as
/// its own service (rather than callers reaching into `ApiClient` directly)
/// so `ThreadedActivityScreen`/`ZendAppModel` depend on a narrow, Phase-2
/// specific surface — matching design.md's "new, separate ActivityDataService
/// class" decision.
class ActivityDataService {
  final ApiClient _apiClient;

  ActivityDataService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<ActivityEdgesResponse> getActivityEdges({
    String? cursor,
    int? limit,
  }) {
    return _apiClient.getActivityEdges(cursor: cursor, limit: limit);
  }

  Future<PoolContributorsResponse> getPoolContributors(String poolId) {
    return _apiClient.getPoolContributors(poolId);
  }

  /// "This person's activity" — used by the Graph_View's node-tap detail
  /// view (Your Mutuals).
  Future<ActivityEdgesResponse> getActivityEdgesForUser(
    String userId, {
    String? cursor,
    int? limit,
  }) {
    return _apiClient.getActivityEdgesForUser(userId, cursor: cursor, limit: limit);
  }

  // ── Reaction counts ─────────────────────────────────────────────────────
  //
  // Every feed card asks for its own reaction counts, because the feed
  // payload doesn't carry them and there's no batch endpoint — so scrolling
  // the Activity list means one HTTP request per card. This cache doesn't
  // remove that N+1, but it removes the parts of it that are pure waste:
  //
  //   * Scrolling a card off-screen and back disposes and rebuilds it. Without
  //     a cache that re-requests counts the client already had.
  //   * Several cards can ask for the same edge at once (the feed and a thread
  //     view showing the same activity). In-flight futures are shared rather
  //     than duplicated.
  //
  // The complete fix is server-side: include reaction counts on the activity
  // edges response, the way transaction_signature/status already are (see
  // ActivityEdge's doc). That's an additive backend change and would delete
  // this cache along with the N+1.
  final Map<String, List<EdgeReactionCount>> _reactionCache = {};
  final Map<String, DateTime> _reactionCachedAt = {};
  final Map<String, Future<List<EdgeReactionCount>>> _reactionsInFlight = {};

  /// Short by design. A reaction count is live social data — stale counts are
  /// cheap to be wrong about for a moment, but not for a whole session.
  static const Duration reactionCacheTtl = Duration(seconds: 90);

  static String _reactionKey(String edgeKind, String edgeId) => '$edgeKind:$edgeId';

  Future<List<EdgeReactionCount>> getEdgeReactions(String edgeKind, String edgeId) {
    final key = _reactionKey(edgeKind, edgeId);

    final cachedAt = _reactionCachedAt[key];
    final cached = _reactionCache[key];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < reactionCacheTtl) {
      return Future.value(cached);
    }

    // Share a request that's already on the wire for this edge instead of
    // firing a second one alongside it.
    final existing = _reactionsInFlight[key];
    if (existing != null) return existing;

    final request = _apiClient.getEdgeReactions(edgeKind, edgeId).then((result) {
      _reactionCache[key] = result;
      _reactionCachedAt[key] = DateTime.now();
      return result;
    }).whenComplete(() => _reactionsInFlight.remove(key));

    _reactionsInFlight[key] = request;
    return request;
  }

  /// Drops the cached counts for one edge, so the next read is authoritative.
  /// Called after the viewer changes their own reaction — showing them a stale
  /// count immediately after they tapped is the one case that reads as broken
  /// rather than merely out of date.
  void invalidateEdgeReactions(String edgeKind, String edgeId) {
    final key = _reactionKey(edgeKind, edgeId);
    _reactionCache.remove(key);
    _reactionCachedAt.remove(key);
  }

  Future<void> addEdgeReaction(String edgeKind, String edgeId, String emoji) async {
    await _apiClient.addEdgeReaction(edgeKind, edgeId, emoji);
    invalidateEdgeReactions(edgeKind, edgeId);
  }

  Future<void> removeEdgeReaction(String edgeKind, String edgeId, String emoji) async {
    await _apiClient.removeEdgeReaction(edgeKind, edgeId, emoji);
    invalidateEdgeReactions(edgeKind, edgeId);
  }

  /// Clears every cached count. Call on sign-out — reaction counts are
  /// per-viewer (`reactedByMe`), so they must not survive an account switch.
  void clearReactionCache() {
    _reactionCache.clear();
    _reactionCachedAt.clear();
    _reactionsInFlight.clear();
  }

  Future<void> makeEdgePublic(String edgeKind, String edgeId, {String preset = 'share_activity_full'}) {
    return _apiClient.makeEdgePublic(edgeKind, edgeId, preset: preset);
  }

  Future<List<EdgeComment>> getEdgeComments(String edgeKind, String edgeId) {
    return _apiClient.getEdgeComments(edgeKind, edgeId);
  }

  Future<void> addEdgeComment(String edgeKind, String edgeId, String body) {
    return _apiClient.addEdgeComment(edgeKind, edgeId, body);
  }

  Future<void> deleteEdgeComment(String edgeKind, String edgeId, String commentId) {
    return _apiClient.deleteEdgeComment(edgeKind, edgeId, commentId);
  }
}
