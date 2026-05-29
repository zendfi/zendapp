class RecentContact {
  RecentContact({
    required this.name,
    required this.tag,
    required this.avatarLabel,
    this.avatarUrl,
  });

  final String name;
  final String tag;
  final String avatarLabel;

  /// CDN URL of the contact's profile photo, if available.
  final String? avatarUrl;

  Map<String, String?> toJson() {
    return {
      'name': name,
      'tag': tag,
      'avatarLabel': avatarLabel,
      'avatarUrl': avatarUrl,
    };
  }

  factory RecentContact.fromJson(Map<String, dynamic> json) {
    return RecentContact(
      name: (json['name'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
      avatarLabel: (json['avatarLabel'] as String?) ?? '',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}
