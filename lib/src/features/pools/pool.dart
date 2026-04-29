import 'dart:math';

const _base62Chars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String generatePoolId() {
  final random = Random();
  return String.fromCharCodes(
    Iterable.generate(
      8,
      (_) => _base62Chars.codeUnitAt(random.nextInt(_base62Chars.length)),
    ),
  );
}

enum PoolStatus { active, completed, expired }

class PoolParticipant {
  const PoolParticipant({
    required this.displayName,
    required this.avatarLabel,
    this.contribution = 0.0,
    this.isExternal = false,
  });

  final String displayName;
  final String avatarLabel;
  final double contribution;
  final bool isExternal;
}

class Pool {
  Pool({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.participants,
    required this.createdAt,
    this.deadline,
    this.gathered = 0.0,
    this.status = PoolStatus.active,
  });

  final String id;
  final String name;
  final double targetAmount;
  final List<PoolParticipant> participants;
  final DateTime createdAt;
  final DateTime? deadline;
  double gathered;
  PoolStatus status;

  /// Progress ratio clamped to [0.0, 1.0].
  double get progress =>
      targetAmount <= 0 ? 0.0 : (gathered / targetAmount).clamp(0.0, 1.0);

  /// Formatted gathered amount as a dollar string.
  String get formattedGathered => '\$${gathered.toStringAsFixed(2)}';

  /// Formatted target amount as a dollar string.
  String get formattedTarget => '\$${targetAmount.toStringAsFixed(2)}';
}
