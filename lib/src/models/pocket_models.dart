class SavingsPocket {
  final String id;
  final String pocketType; // "free" | "goal" | "lock"
  final double balanceUsd;
  final double pocketYieldUsd;
  // Goal fields (nullable)
  final String? goalName;
  final String? goalEmoji;
  final double? goalTargetUsd;
  final String? goalDeadline;
  final String? goalMode; // "flexible" | "strict"
  final double? goalProgress; // 0.0–100.0
  // Lock fields (nullable)
  final String? lockUnlockDate;
  final int? lockDaysRemaining;
  final bool? lockExpired;

  const SavingsPocket({
    required this.id,
    required this.pocketType,
    required this.balanceUsd,
    required this.pocketYieldUsd,
    this.goalName,
    this.goalEmoji,
    this.goalTargetUsd,
    this.goalDeadline,
    this.goalMode,
    this.goalProgress,
    this.lockUnlockDate,
    this.lockDaysRemaining,
    this.lockExpired,
  });

  factory SavingsPocket.fromJson(Map<String, dynamic> json) {
    return SavingsPocket(
      id: json['id'] as String,
      pocketType: json['pocket_type'] as String,
      balanceUsd: (json['balance_usd'] as num).toDouble(),
      pocketYieldUsd: (json['pocket_yield_usd'] as num).toDouble(),
      goalName: json['goal_name'] as String?,
      goalEmoji: json['goal_emoji'] as String?,
      goalTargetUsd: (json['goal_target_usd'] as num?)?.toDouble(),
      goalDeadline: json['goal_deadline'] as String?,
      goalMode: json['goal_mode'] as String?,
      goalProgress: (json['goal_progress'] as num?)?.toDouble(),
      lockUnlockDate: json['lock_unlock_date'] as String?,
      lockDaysRemaining: json['lock_days_remaining'] as int?,
      lockExpired: json['lock_expired'] as bool?,
    );
  }

  // Convenience getters
  bool get isFree => pocketType == 'free';
  bool get isGoal => pocketType == 'goal';
  bool get isLock => pocketType == 'lock';

  bool get isGoalLocked =>
      isGoal &&
      goalMode == 'strict' &&
      (goalProgress ?? 0) < 100 &&
      lockExpired != true;

  bool get isLockExpired => isLock && (lockExpired ?? false);
}

class CreateGoalRequest {
  final String name;
  final String emoji;
  final double targetUsd;
  final String? deadline; // ISO 8601 date
  final String mode; // "flexible" | "strict"

  const CreateGoalRequest({
    required this.name,
    required this.emoji,
    required this.targetUsd,
    this.deadline,
    required this.mode,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'emoji': emoji,
      'target_usd': targetUsd,
      'mode': mode,
    };
    if (deadline != null) map['deadline'] = deadline;
    return map;
  }
}

class CreateLockRequest {
  final double amountUsd;
  final String unlockDate; // ISO 8601 date

  const CreateLockRequest({
    required this.amountUsd,
    required this.unlockDate,
  });

  Map<String, dynamic> toJson() => {
        'amount_usd': amountUsd,
        'unlock_date': unlockDate,
      };
}
