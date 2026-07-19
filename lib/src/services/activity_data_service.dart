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

  Future<List<EdgeReactionCount>> getEdgeReactions(String edgeKind, String edgeId) {
    return _apiClient.getEdgeReactions(edgeKind, edgeId);
  }

  Future<void> addEdgeReaction(String edgeKind, String edgeId, String emoji) {
    return _apiClient.addEdgeReaction(edgeKind, edgeId, emoji);
  }

  Future<void> removeEdgeReaction(String edgeKind, String edgeId, String emoji) {
    return _apiClient.removeEdgeReaction(edgeKind, edgeId, emoji);
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
