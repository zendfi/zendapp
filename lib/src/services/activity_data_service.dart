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
}
