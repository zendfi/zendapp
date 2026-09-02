import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../navigation/zend_routes.dart';
import '../../navigation/zend_shell_controller.dart';
import '../activity/activity_comment_sheet.dart';
import '../activity/activity_grouping.dart';
import '../activity/activity_receipt_builder.dart';
import '../activity/transaction_receipt_sheet.dart';
import '../dm/dm_thread_screen.dart';
import '../shell/zend_entry_sheet.dart';
import 'account_information_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Person page — ZEND BETA spec §18-20.
///
/// "A person page is a miniature one-to-one relationship feed. It isn't a
/// public social profile." Structure per spec: avatar, @tag, activity
/// count, then Chat/Zend buttons, then the actual activity list — not a
/// bio/mutual-context-card/streak-card social profile. Reachable from
/// search results, People's Recent/discovery rows, activity threads, DM
/// headers, and zdfi.me/@username deep links.
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
  String? _userId;
  String? _zendtag;
  String? _displayName;
  String? _avatarUrl;
  bool _loadingIdentity = true;
  String? _identityError;

  List<ActivityEdge> _edges = [];
  bool _loadingEdges = true;
  String? _edgesError;

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
  }

  bool get _isOwnProfile {
    final model = ZendScope.of(context);
    if (_userId == null && _zendtag == null) return false;
    return _userId == model.currentUserId ||
        (_zendtag != null && _zendtag!.toLowerCase() == model.currentZendtag?.toLowerCase());
  }

  Future<void> _resolveIdentity() async {
    final model = ZendScope.of(context);
    setState(() {
      _loadingIdentity = true;
      _identityError = null;
    });
    try {
      if (widget.zendtag != null) {
        // getUserProfile (not zendtagService.resolve) — the resolve
        // endpoint doesn't return a userId, and the activity-edges fetch
        // below needs one. This screen just doesn't render the
        // bio/mutual-context/streak fields the fuller response also
        // carries — spec §18-30 wants avatar/tag/count only.
        final profile = await model.walletService.apiClient.getUserProfile(widget.zendtag!);
        if (!mounted) return;
        setState(() {
          _userId = profile.userId;
          _zendtag = profile.zendtag;
          _displayName = profile.displayName.trim().isNotEmpty ? profile.displayName : '@${profile.zendtag}';
          _avatarUrl = profile.avatarUrl;
          _loadingIdentity = false;
        });
        _loadEdges();
      } else {
        // userId-only entry (e.g. Person page reached from a userId-keyed
        // source) — use whatever the caller already knew and let the
        // activity-edges fetch below be the actual data source; no
        // additional identity round-trip needed.
        setState(() {
          _userId = widget.userId;
          _displayName = widget.knownDisplayName;
          _avatarUrl = widget.knownAvatarUrl;
          _loadingIdentity = false;
        });
        _loadEdges();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _identityError = 'Could not load this profile';
          _loadingIdentity = false;
        });
      }
    }
  }

  Future<void> _loadEdges() async {
    if (_userId == null) {
      setState(() => _loadingEdges = false);
      return;
    }
    final model = ZendScope.of(context);
    setState(() {
      _loadingEdges = true;
      _edgesError = null;
    });
    try {
      final response = await model.activityDataService.getActivityEdgesForUser(_userId!, limit: 50);
      if (mounted) {
        setState(() {
          _edges = response.edges;
          _loadingEdges = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _edgesError = e.toString();
          _loadingEdges = false;
        });
      }
    }
  }

  String get _label {
    if (_zendtag != null && _zendtag!.isNotEmpty) return '@$_zendtag';
    if (_displayName != null && _displayName!.isNotEmpty) return _displayName!;
    return 'Zend user';
  }

  String get _initial => _label.startsWith('@')
      ? (_label.length > 1 ? _label[1].toUpperCase() : '?')
      : (_label.isNotEmpty ? _label[0].toUpperCase() : '?');

  void _openDm() {
    final model = ZendScope.of(context);
    if (model.currentUserId == null || _userId == null) return;

    final existing = model.dmService.cachedThreads.where((t) => t.counterparty.userId == _userId).firstOrNull;
    if (existing != null) {
      pushZendSlide(context, DmThreadScreen(roomId: existing.roomId, counterparty: existing.counterparty));
      return;
    }

    model.dmService.getOrCreateRoom(_userId!).then((result) {
      if (!context.mounted) return;
      pushZendSlide(
        context, // ignore: use_build_context_synchronously
        DmThreadScreen(roomId: result.roomId, counterparty: result.counterparty),
      );
    }).catchError((_) {
      if (context.mounted) {
        ZendShellController.instance?.switchToTab(2);
      }
    });
  }

  void _openZend() {
    // Contextual identity — spec §20: "The user should not have to select
    // James again." Preselects whichever identity string we already have.
    showZendEntrySheet(context, prefilledRecipient: _zendtag);
  }

  String _describeEdge(ActivityEdge edge) {
    final verb = feedVerbFor(edge);
    if (edge.direction == 'external') {
      return '${edge.senderZendtag != null ? '@${edge.senderZendtag}' : 'Someone'} $verb '
          '${edge.recipientZendtag != null ? '@${edge.recipientZendtag}' : 'someone'}';
    }
    final isSelfSender = edge.direction == 'outgoing';
    return isSelfSender ? 'You $verb $_label' : '$_label $verb';
  }

  void _openReceipt(ActivityEdge edge) {
    final model = ZendScope.of(context);
    final entry = entryFromEdgeForViewer(edge, model);
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details for this activity are not available', style: TextStyle(fontFamily: 'Geist'))),
      );
      return;
    }
    final tx = zendTransactionFromEdge(edge, entry, avatarLabel: edge.counterparty.initialLetter, avatarUrl: edge.counterparty.avatarUrl);
    showTransactionReceipt(context, tx: tx);
  }

  void _openActivity(ActivityEdge edge, String headline) {
    final isExternal = edge.direction == 'external';
    showActivityCommentSheet(
      context,
      edge: edge,
      headline: headline,
      avatarUrl: isExternal ? edge.senderAvatarUrl : _avatarUrl,
      avatarInitial: isExternal
          ? (edge.senderZendtag?.isNotEmpty == true ? edge.senderZendtag![0].toUpperCase() : '?')
          : _initial,
      onViewReceipt: () => _openReceipt(edge),
      onOpenChat: isExternal ? null : _openDm,
    );
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                  ),
                ],
              ),
            ),
            if (_loadingIdentity)
              const Expanded(child: UserProfileSkeleton())
            else if (_identityError != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_identityError!, style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _resolveIdentity,
                        child: Text('Retry', style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.accent)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // ── Hero: avatar, tag, activity count (spec §18) ──
                    Center(
                      child: Column(
                        children: [
                          ZendAvatar(radius: 40, photoUrl: _avatarUrl, initials: _initial),
                          const SizedBox(height: 12),
                          Text(
                            _label,
                            style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 20, color: zt.textPrimary),
                          ),
                          if (!_loadingEdges) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_edges.length} activit${_edges.length == 1 ? 'y' : 'ies'} together',
                              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── Chat / Zend (own profile gets Edit instead — spec §1.5) ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _isOwnProfile
                          ? OutlineActionButton(
                              label: 'Edit profile',
                              onPressed: () => pushZendSlide(context, const AccountInformationScreen()),
                            )
                          : Row(
                              children: [
                                Expanded(child: OutlineActionButton(label: 'Chat', onPressed: _openDm)),
                                const SizedBox(width: 12),
                                Expanded(child: PrimaryButton(label: 'Zend', onPressed: _openZend)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),
                    Divider(color: zt.border, height: 1),
                    const SizedBox(height: 8),
                    // ── Activities — the miniature relationship feed ──
                    Expanded(
                      child: _loadingEdges
                          ? const PersonActivitySkeleton()
                          : _edgesError != null
                              ? ZendErrorState(
                                  title: "Couldn't load activity",
                                  onRetry: _loadEdges,
                                )
                              : _edges.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No activity yet',
                                        style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                      itemCount: _edges.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                                      itemBuilder: (context, i) {
                                        final edge = _edges[i];
                                        final headline = _describeEdge(edge);
                                        return _PersonActivityRow(
                                          headline: headline,
                                          edge: edge,
                                          onTap: () => _openActivity(edge, headline),
                                        );
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonActivityRow extends StatelessWidget {
  const _PersonActivityRow({required this.headline, required this.edge, required this.onTap});

  final String headline;
  final ActivityEdge edge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amountLabel = edge.amountHidden ? 'Hidden' : '\$${edge.amountUsdc ?? '0'}';

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
                    ),
                    if (edge.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        edge.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Geist', fontSize: 12.5, color: zt.textPrimary.withValues(alpha: 0.85)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amountLabel,
                style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: zt.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
