import 'package:flutter/widgets.dart';

import 'zend_state.dart';

/// Rebuilds its subtree only when the slice of [ZendAppModel] it cares about
/// actually changes.
///
/// ── The problem this solves ─────────────────────────────────────────────
/// [ZendScope] is an `InheritedNotifier`, which has no notion of *which* part
/// of the model changed. Any `notifyListeners()` marks every dependent
/// element dirty, and a single SSE transfer event fans out into several
/// notifies (patch, then balance, history and activity refetches). So a
/// screen that reads one field ends up rebuilding on everything.
///
/// It isn't enough to short-circuit the *work* inside build — the widgets
/// themselves get rebuilt, and for a list that means rebuilding every visible
/// row to produce output identical to what was already on screen.
///
/// ── How it works ───────────────────────────────────────────────────────
/// This element is still a dependent, so it still rebuilds on every notify —
/// that part is unavoidable. What it does is run [selector] (cheap) and, when
/// the result is unchanged, return the **same widget instance** it returned
/// last time. `Element.updateChild` short-circuits on an identical widget
/// instance, so the entire subtree below is skipped: not rebuilt, not laid
/// out, not repainted.
///
/// ── Contract ───────────────────────────────────────────────────────────
/// [builder] must be a pure function of ([selector]'s result, [child]).
/// Anything else it closes over will be captured in the cached widget and go
/// stale, because the whole point is that it is not re-invoked while the
/// selected value compares equal.
///
/// [T] must have meaningful `==`. For a collection that is normally identity,
/// which is usually what you want: assign a new list only when the contents
/// really changed, and the subtree is skipped the rest of the time.
///
/// ```dart
/// ZendSelector<int>(
///   selector: (model) => model.dmUnreadTotal,
///   builder: (context, unread, _) => Badge(count: unread),
/// )
/// ```
class ZendSelector<T> extends StatefulWidget {
  const ZendSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.child,
  });

  /// Pulls the value this subtree depends on out of the model. Runs on every
  /// notify, so it should be cheap — a field read or a record of a few.
  final T Function(ZendAppModel model) selector;

  /// Builds the subtree. Called only when [selector]'s result changes.
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  /// Optional pre-built subtree passed through to [builder], for parts that
  /// never depend on the selected value at all.
  final Widget? child;

  @override
  State<ZendSelector<T>> createState() => _ZendSelectorState<T>();
}

class _ZendSelectorState<T> extends State<ZendSelector<T>> {
  T? _value;
  Widget? _cached;
  bool _hasValue = false;

  @override
  void didUpdateWidget(ZendSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only `child` invalidates the cache.
    //
    // Deliberately NOT comparing [selector] or [builder]: they are almost
    // always written as inline closures, and a fresh closure instance is
    // never `==` to the previous one. Invalidating on that would reset the
    // cache on every single parent rebuild, so this widget would compile,
    // read correctly, and silently do nothing — the worst possible failure
    // mode for an optimisation. (This matches how provider's `Selector`
    // behaves, and is why [builder] is contractually a pure function of its
    // inputs.)
    //
    // Practical consequence: editing a builder's body under hot reload won't
    // show until the selected value next changes. Hot restart does.
    if (oldWidget.child != widget.child) {
      _hasValue = false;
      _cached = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribes this element (and only this element) to the model.
    final model = ZendScope.of(context);
    final next = widget.selector(model);

    if (!_hasValue || _cached == null || next != _value) {
      _value = next;
      _hasValue = true;
      _cached = widget.builder(context, next, widget.child);
    }

    // Returning the identical instance is what makes the subtree skip.
    return _cached!;
  }
}
