import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_models.dart';
import '../../navigation/zend_routes.dart';
import '../../navigation/zend_shell_controller.dart';
import '../dm/dm_thread_screen.dart';
import '../send/qr_payment_sheet.dart';
import '../../models/qr_payment_intent.dart';
import 'account_information_screen.dart';
import 'package:solar_icons/solar_icons.dart';

/// Public user profile screen — reachable from search results, activity
/// threads, DM headers, and zdfi.me/@username deep links.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    this.zendtag,
    this.userId,
    this.knownDisplayName,
    this.knownAvatarUrl,
  }) : assert(zendtag != null || userId != null,
            'Either zendtag or userId must be provided');

  final String? zendtag;
  final String? userId;
  final String? knownDisplayName;
  final String? knownAvatarUrl;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicUserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      // Use zendtag if available, otherwise resolve from userId
      final tag = widget.zendtag ??
          await _resolveTagFromUserId(model, widget.userId!);
      if (tag == null) throw Exception('User not found');
      final profile = await model.walletService.apiClient.getUserProfile(tag);
      if (mounted) {
        setState(() {
          _profile = profile;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load profile';
          _loading = false;
        });
      }
    }
  }

  Future<String?> _resolveTagFromUserId(ZendAppModel model, String userId) async {
    // userId resolution not yet implemented — callers should always provide zendtag
    return null;
  }

  bool get _isOwnProfile {
    final model = ZendScope.of(context);
    if (_profile == null) return false;
    return _profile!.userId == model.currentUserId ||
        _profile!.zendtag.toLowerCase() ==
            model.currentZendtag?.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(SolarIconsBold.altArrowLeft,
                        color: zt.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ZendLoader())
                  : _error != null
                      ? _ErrorState(
                          message: _error!,
                          onRetry: _loadProfile,
                        )
                      : _ProfileContent(
                          profile: _profile!,
                          isOwnProfile: _isOwnProfile,
                          onRefresh: _loadProfile,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.isOwnProfile,
    required this.onRefresh,
  });

  final PublicUserProfile profile;
  final bool isOwnProfile;
  final VoidCallback onRefresh;

  void _openDm(BuildContext context, PublicUserProfile profile) {
    final model = ZendScope.of(context);
    if (model.currentUserId == null || profile.userId.isEmpty) return;

    // Check cache first for instant navigation
    final existing = model.dmService.cachedThreads
        .where((t) => t.counterparty.userId == profile.userId)
        .firstOrNull;

    if (existing != null) {
      pushZendSlide(
        context,
        DmThreadScreen(roomId: existing.roomId, counterparty: existing.counterparty),
      );
      return;
    }

    // No cached thread — get the server-canonical room_id (creates the room
    // if it doesn't exist yet). Show a brief loading indicator via async nav.
    model.dmService.getOrCreateRoom(profile.userId).then((result) {
      if (!context.mounted) return;
      pushZendSlide(
        context, // ignore: use_build_context_synchronously
        DmThreadScreen(
          roomId: result.roomId,
          counterparty: result.counterparty,
        ),
      );
    }).catchError((_) {
      // Fallback: switch to Messages tab — user can find/start the thread there
      if (context.mounted) {
        ZendShellController.instance?.switchToTab(3);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero ──────────────────────────────────────────────────────────
          Column(
            children: [
              const SizedBox(height: 8),
              ZendAvatar(
                radius: 44,
                photoUrl: profile.avatarUrl,
                initials: profile.initialLetter,
              ),
              const SizedBox(height: 14),
              Text(
                profile.displayName,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 26,
                  color: zt.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '@${profile.zendtag}',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 13,
                  color: zt.textSecondary,
                ),
              ),
              if (profile.bio?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Text(
                  profile.bio!,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: zt.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // ── Action buttons ─────────────────────────────────────────────────
          if (isOwnProfile)
            OutlineActionButton(
              label: 'Edit profile',
              onPressed: () =>
                  pushZendSlide(context, const AccountInformationScreen()),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: SolarIconsBold.dollar,
                        label: 'Send',
                        onTap: () {
                          Navigator.of(context).pop();
                          showQrPaymentSheet(
                            context,
                            intent: QrPaymentIntent(zendtag: profile.zendtag),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: SolarIconsBold.squareArrowRightUp,
                        label: 'Request',
                        onTap: () {
                          Navigator.of(context).pop();
                          showQrPaymentSheet(
                            context,
                            intent: QrPaymentIntent(zendtag: profile.zendtag),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: SolarIconsBold.chatDots,
                        label: 'Message',
                        onTap: () => _openDm(context, profile),
                      ),
                    ),
                  ],
                ),
              ],
            ),

          const SizedBox(height: 20),

          // ── Mutual context ─────────────────────────────────────────────────
          if (!isOwnProfile && profile.mutualContext != null) ...[
            _MutualContextCard(context: profile.mutualContext!),
            const SizedBox(height: 16),
          ],

          // ── Streak placeholder (wired in Phase 3) ─────────────────────────
          if (!isOwnProfile) ...[
            Builder(builder: (ctx) {
              final streak = model.activeStreaks[profile.userId];
              if (streak == null || !streak.isActive) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _StreakCard(streakWeeks: streak.streakWeeks, longestStreak: streak.longestStreak),
              );
            }),
          ],

          // ── Public activity count hint ─────────────────────────────────────
          if (profile.publicActivityCount > 0 && !isOwnProfile) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '${profile.publicActivityCount} shared activities',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: zt.textSecondary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.xl),
              ),
              child: Text(
                'Tap Activity to see shared posts',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: zt.accentBright),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MutualContextCard extends StatelessWidget {
  const _MutualContextCard({required this.context});
  final MutualContext context;

  @override
  Widget build(BuildContext buildContext) {
    final zt = ZendTheme.of(buildContext);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: zt.accentBright.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      child: Row(
        children: [
          Icon(SolarIconsBold.transferHorizontal,
              size: 16, color: zt.accentBright),
          const SizedBox(width: 10),
          Text(
            "You've sent each other ${context.transactionCount} time${context.transactionCount == 1 ? '' : 's'}"
            " · \$${context.totalUsdc} total",
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.accentBright,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streakWeeks, required this.longestStreak});
  final int streakWeeks;
  final int longestStreak;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$streakWeeks week streak',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: zt.textPrimary,
                  ),
                ),
                Text(
                  'Longest: $longestStreak weeks',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text('Retry',
                style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 14, color: zt.accent)),
          ),
        ],
      ),
    );
  }
}
