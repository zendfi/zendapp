/// The ZApp a bot account is linked to (`automated_app` on people payloads).
/// Shown as "from {name}" next to the bot's Automated mark; tapping it opens the app.
class BotApp {
  const BotApp({required this.slug, required this.name});
  final String slug;
  final String name;

  static BotApp? fromJson(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    final name = json['name'];
    if (slug is! String || slug.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return BotApp(slug: slug, name: name);
  }
}

/// "Automated" or "Automated · from Kobolt", for under a bot's name.
String automatedLabel(BotApp? app) =>
    app == null ? 'Automated' : 'Automated · from ${app.name}';
