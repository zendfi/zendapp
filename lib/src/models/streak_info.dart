class StreakInfo {
  const StreakInfo({
    required this.counterpartyUserId,
    required this.counterpartyZendtag,
    required this.counterpartyDisplayName,
    this.counterpartyAvatarUrl,
    required this.streakWeeks,
    required this.longestStreak,
    this.streakStartedAt,
  });

  final String counterpartyUserId;
  final String counterpartyZendtag;
  final String counterpartyDisplayName;
  final String? counterpartyAvatarUrl;
  final int streakWeeks;
  final int longestStreak;
  final DateTime? streakStartedAt;

  /// A streak is considered active and worth displaying when ≥ 2 weeks.
  bool get isActive => streakWeeks >= 2;

  factory StreakInfo.fromJson(Map<String, dynamic> json) {
    return StreakInfo(
      counterpartyUserId: json['counterparty_user_id'] as String? ?? '',
      counterpartyZendtag: json['counterparty_zendtag'] as String? ?? '',
      counterpartyDisplayName: json['counterparty_display_name'] as String? ?? '',
      counterpartyAvatarUrl: json['counterparty_avatar_url'] as String?,
      streakWeeks: json['streak_weeks'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      streakStartedAt: json['streak_started_at'] != null
          ? DateTime.tryParse(json['streak_started_at'] as String)
          : null,
    );
  }
}
