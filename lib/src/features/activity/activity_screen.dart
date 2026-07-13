import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'graph_view_screen.dart';
import 'legacy_activity_list_view.dart';
import 'threaded_activity_screen.dart';

/// Thin router between the Phase 2 [ThreadedActivityScreen] (default), the
/// pre-redesign [LegacyActivityListView], and the Phase 3 opt-in
/// [GraphViewScreen] — persisted via `SharedPreferences` under
/// `activity_view_mode` (Req 12.1, 12.2, 16.4, 16.5, 16.6).
///
/// All of the original `activity_screen.dart` body (filter pills,
/// `_buildItems`, tap-through sheets) now lives, unchanged, in
/// `legacy_activity_list_view.dart` — this file only decides which of the
/// three full-screen views to render.
///
/// [GraphViewScreen] is reachable only via an explicit opt-in control on
/// [ThreadedActivityScreen]'s header (Req 16.5). Req 16.4 ("Threaded is the
/// default shown on first load") and Req 16.6 ("the toggle choice persists
/// across sessions") are reconciled the same way Req 12.1/12.2 already are
/// for the Legacy toggle: `_modeThreaded` is only a *fallback* for a User
/// who has never explicitly chosen a mode (a fresh install, no persisted
/// key yet) — once a User explicitly picks Graph_View, that choice is
/// persisted under the same `activity_view_mode` key and is what "first
/// load" resolves to on every subsequent app session for that User.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _prefsKey = 'activity_view_mode';
  static const _modeThreaded = 'threaded';
  static const _modeLegacy = 'legacy';
  static const _modeGraph = 'graph';

  // Default: threaded (Req 12.1, Req 16.4).
  String _mode = _modeThreaded;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _mode = prefs.getString(_prefsKey) ?? _modeThreaded;
        _loaded = true;
      });
    }
  }

  Future<void> _setMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode);
    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      // Avoid a flash of the wrong view while the persisted preference loads.
      return const SizedBox.shrink();
    }

    switch (_mode) {
      case _modeLegacy:
        return LegacyActivityListView(
          onToggleView: () => _setMode(_modeThreaded),
        );
      case _modeGraph:
        return GraphViewScreen(
          onToggleView: () => _setMode(_modeThreaded),
        );
      default:
        return ThreadedActivityScreen(
          onToggleView: () => _setMode(_modeLegacy),
          onOpenGraphView: () => _setMode(_modeGraph),
        );
    }
  }
}
