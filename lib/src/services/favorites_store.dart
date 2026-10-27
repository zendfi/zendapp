import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// People pinned to the top of the People tab (design revamp: Favorites).
///
/// Device-local, keyed by handle. Kept deliberately simple: favourites are a
/// shortcut, not data the server needs to know about.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  static const _key = 'zend_favorite_tags';
  Set<String> _tags = {};
  bool _loaded = false;

  Set<String> get tags => Set.unmodifiable(_tags);
  bool isFavorite(String tag) => _tags.contains(tag.toLowerCase());

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _tags = (prefs.getStringList(_key) ?? const []).toSet();
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggle(String tag) async {
    final t = tag.toLowerCase();
    _tags.contains(t) ? _tags.remove(t) : _tags.add(t);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _tags.toList());
  }
}
