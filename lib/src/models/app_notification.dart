/// One item in the notifications inbox (`GET /api/zend/notifications`).
///
/// [data] is the same payload a push carries, so tapping an item opens the
/// same screen a push tap would (`NotificationDestination.fromData`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.data,
    required this.count,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String category;
  final String title;
  final String body;
  final Map<String, dynamic> data;

  /// Messages collapsed into this item (one row per chat while unread).
  final int count;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};
    final type = json['type'] as String? ?? '';
    // Destinations are parsed from `data['type']`; make sure it's there.
    data.putIfAbsent('type', () => type);
    return AppNotification(
      id: json['id'] as String? ?? '',
      type: type,
      category: json['category'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: data,
      count: (json['count'] as num?)?.toInt() ?? 1,
      read: json['read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  AppNotification markedRead() => AppNotification(
    id: id,
    type: type,
    category: category,
    title: title,
    body: body,
    data: data,
    count: count,
    read: true,
    createdAt: createdAt,
  );
}
