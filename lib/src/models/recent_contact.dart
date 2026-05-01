class RecentContact {
  RecentContact({
    required this.name,
    required this.tag,
    required this.avatarLabel,
  });

  final String name;
  final String tag;
  final String avatarLabel;

  Map<String, String> toJson() {
    return {
      'name': name,
      'tag': tag,
      'avatarLabel': avatarLabel,
    };
  }

  factory RecentContact.fromJson(Map<String, dynamic> json) {
    return RecentContact(
      name: (json['name'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
      avatarLabel: (json['avatarLabel'] as String?) ?? '',
    );
  }
}
