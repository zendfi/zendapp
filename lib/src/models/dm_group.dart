import 'dm_thread.dart';

/// One person in a group.
class DmGroupMember {
  const DmGroupMember({
    required this.userId,
    required this.zendtag,
    required this.displayName,
    this.avatarUrl,
    required this.role,
  });

  final String userId;
  final String zendtag;
  final String displayName;
  final String? avatarUrl;

  /// `owner`, `admin` or `member`.
  final String role;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || role == 'owner';

  String get initialLetter =>
      zendtag.isNotEmpty ? zendtag[0].toUpperCase() : '?';

  DmCounterparty asCounterparty() => DmCounterparty(
    userId: userId,
    zendtag: zendtag,
    displayName: displayName,
    avatarUrl: avatarUrl,
  );

  factory DmGroupMember.fromJson(Map<String, dynamic> json) => DmGroupMember(
    userId: json['user_id'] as String? ?? '',
    zendtag: json['zendtag'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String?,
    role: json['role'] as String? ?? 'member',
  );
}

/// Full group details from GET /api/zend/dm/groups/:room_id.
class DmGroupDetail {
  const DmGroupDetail({
    required this.roomId,
    required this.name,
    this.emoji,
    required this.members,
    required this.myRole,
    required this.muted,
    required this.maxMembers,
  });

  final String roomId;
  final String name;
  final String? emoji;
  final List<DmGroupMember> members;
  final String myRole;
  final bool muted;
  final int maxMembers;

  bool get iAmAdmin => myRole == 'owner' || myRole == 'admin';
  bool get iAmOwner => myRole == 'owner';
  bool get isFull => members.length >= maxMembers;

  factory DmGroupDetail.fromJson(Map<String, dynamic> json) {
    final emoji = (json['emoji'] as String?)?.trim();
    return DmGroupDetail(
      roomId: json['room_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Group',
      emoji: emoji == null || emoji.isEmpty ? null : emoji,
      members: (json['members'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DmGroupMember.fromJson)
          .toList(),
      myRole: json['my_role'] as String? ?? 'member',
      muted: json['muted'] as bool? ?? false,
      maxMembers: (json['max_members'] as num?)?.toInt() ?? 20,
    );
  }
}
