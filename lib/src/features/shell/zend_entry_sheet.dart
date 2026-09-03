import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/recent_contact.dart';
import '../request/request_drawer_sheet.dart';
import '../send/send_flow_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The Zend entry point — identity-first, per ZEND BETA spec §10-16.
///
/// "The user first identifies WHO. This is fundamental to Zend's
/// philosophy." Three stages, presented as a single sheet:
///
///   1. Identity — search by @username or email, or pick from Recent.
///   2. Intent — once identity is established, choose Send or Request.
///   3. Hand-off — delegates to the existing [SendFlowSheet] /
///      [RequestDrawerSheet] with the identity pre-filled, so the amount
///      keypad + PIN + confirmation flow isn't duplicated here.
///
/// This sheet deliberately does NOT re-implement amount entry, PIN,
/// confirmation, or state-model handling (pending/confirmed/failed) — all
/// of that already exists correctly in SendFlowSheet/RequestDrawerSheet and
/// re-implementing it here would fork behaviour we've already verified.
/// Its only job is identity resolution + intent selection, then handing
/// off. Once a dedicated Send/Request visual redesign happens, this file's
/// hand-off calls are the only place that needs to change.
Future<void> showZendEntrySheet(
  BuildContext context, {
  String? prefilledRecipient,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1.0,
      child: ZendEntrySheet(prefilledRecipient: prefilledRecipient),
    ),
  );
}

class ZendEntrySheet extends StatefulWidget {
  const ZendEntrySheet({super.key, this.prefilledRecipient});

  /// Skips straight to the Intent stage with this identity already
  /// resolved — used when Zend is invoked contextually (e.g. from inside
  /// a Chat or a Person page), where the identity is already known and
  /// shouldn't be re-selected (spec §20/§27: "Context should remove work,
  /// not remove control").
  final String? prefilledRecipient;

  @override
  State<ZendEntrySheet> createState() => _ZendEntrySheetState();
}

enum _EntryStage { identity, intent, sendAmount }

class _ZendEntrySheetState extends State<ZendEntrySheet> {
  late _EntryStage _stage;
  final _searchController = TextEditingController();
  final _sendAmountController = TextEditingController();
  final _sendNoteController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  String? _identityError;

  // Resolved identity, once established.
  String? _zendtag;
  String? _email;
  String? _displayName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledRecipient != null) {
      _stage = _EntryStage.intent;
      _zendtag = widget.prefilledRecipient;
      _displayName = widget.prefilledRecipient;
    } else {
      _stage = _EntryStage.identity;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sendAmountController.dispose();
    _sendNoteController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _results = [];
      _identityError = null;
    });
    _debounce?.cancel();
    if (_query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(_query));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final model = ZendScope.of(context);
      final results = await model.walletService.apiClient.searchUsers(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submitRaw() async {
    final raw = _query;
    if (raw.isEmpty) return;

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (emailRegex.hasMatch(raw)) {
      // Non-Zend recipient by email — spec §15: same identity-first
      // treatment, just without a Zend username at the end of it.
      setState(() {
        _email = raw;
        _displayName = raw.split('@').first;
        _zendtag = null;
        _avatarUrl = null;
        _stage = _EntryStage.intent;
      });
      return;
    }

    final tag = raw.replaceAll('@', '').toLowerCase();
    setState(() => _searching = true);
    try {
      final model = ZendScope.of(context);
      final resolved = await model.zendtagService.resolve(tag);
      if (!mounted) return;
      setState(() {
        _zendtag = resolved.zendtag;
        _displayName = resolved.displayName.trim().isNotEmpty ? resolved.displayName : '@${resolved.zendtag}';
        _avatarUrl = resolved.avatarUrl;
        _email = null;
        _searching = false;
        _stage = _EntryStage.intent;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _identityError = "We couldn't find anyone with that identity. Check the username or email and try again.";
      });
    }
  }

  void _pickContact(RecentContact c) {
    setState(() {
      _zendtag = c.tag;
      _displayName = c.name.isNotEmpty ? c.name : c.tag;
      _avatarUrl = c.avatarUrl;
      _email = null;
      _stage = _EntryStage.intent;
    });
  }

  void _pickSearchResult(Map<String, dynamic> u) {
    final tag = u['zendtag'] as String? ?? '';
    setState(() {
      _zendtag = tag;
      _displayName = (u['display_name'] as String?)?.trim().isNotEmpty == true
          ? u['display_name'] as String
          : '@$tag';
      _avatarUrl = u['avatar_url'] as String?;
      _email = null;
      _stage = _EntryStage.intent;
    });
  }

  void _goToSendAmount() {
    setState(() => _stage = _EntryStage.sendAmount);
  }

  void _confirmSendAmount() {
    final amount = double.tryParse(_sendAmountController.text.trim()) ?? 0;
    if (amount <= 0) return;
    Navigator.of(context).pop();
    showSendFlowSheet(
      context,
      amount: amount,
      prefilledRecipient: _zendtag ?? _email,
      prefilledNote: _sendNoteController.text.trim().isEmpty ? null : _sendNoteController.text.trim(),
    );
  }

  void _openRequest() {
    Navigator.of(context).pop();
    showRequestDrawer(
      context,
      prefilledRecipient: _zendtag ?? _email,
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: ZendSheetHandle()),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: ZendMotion.sheetEnter,
                child: switch (_stage) {
                  _EntryStage.identity => _buildIdentityStage(zt),
                  _EntryStage.intent => _buildIntentStage(zt),
                  _EntryStage.sendAmount => _buildSendAmountStage(zt),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityStage(ZendTheme zt) {
    final model = ZendScope.of(context);
    return Padding(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Zend',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 24, fontWeight: FontWeight.w700, color: zt.textPrimary),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _submitRaw(),
              style: TextStyle(fontFamily: 'Geist', fontSize: 16, color: zt.textPrimary),
              decoration: InputDecoration(
                hintText: '@username or email',
                hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 16, color: zt.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          if (_identityError != null) ...[
            const SizedBox(height: 8),
            Text(
              _identityError!,
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ZendColors.destructive),
            ),
          ],
          const SizedBox(height: 20),
          if (_query.length >= 2) ..._buildLiveResults(zt) else ..._buildRecent(zt, model.recentContacts),
        ],
      ),
    );
  }

  List<Widget> _buildLiveResults(ZendTheme zt) {
    if (_searching && _results.isEmpty) {
      // Skeleton rows shaped like the real identity rows below them
      // (avatar + two text lines) rather than a spinner — the loading
      // state previews the shape of what's about to appear instead of
      // just signaling "wait".
      return const [SearchUsersSkeleton()];
    }
    if (_results.isEmpty) {
      return [];
    }
    return _results.map((u) {
      final tag = u['zendtag'] as String? ?? '';
      final name = (u['display_name'] as String?)?.trim().isNotEmpty == true ? u['display_name'] as String : tag;
      return _IdentityRow(
        displayName: name,
        subtitle: '@$tag',
        avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
        avatarUrl: u['avatar_url'] as String?,
        onTap: () => _pickSearchResult(u),
      );
    }).toList();
  }

  List<Widget> _buildRecent(ZendTheme zt, List<RecentContact> recent) {
    if (recent.isEmpty) return [];
    return [
      Text(
        'Recent',
        style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
      ),
      const SizedBox(height: 4),
      ...recent.take(6).map((c) => _IdentityRow(
            displayName: c.name.isNotEmpty ? c.name : c.tag,
            subtitle: '@${c.tag}',
            avatarLabel: c.avatarLabel,
            avatarUrl: c.avatarUrl,
            onTap: () => _pickContact(c),
          )),
    ];
  }

  Widget _buildIntentStage(ZendTheme zt) {
    return Padding(
      key: const ValueKey('intent'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: widget.prefilledRecipient != null
                  ? null
                  : () => setState(() => _stage = _EntryStage.identity),
              child: widget.prefilledRecipient == null
                  ? Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary, size: 22)
                  : const SizedBox(height: 22),
            ),
          ),
          const SizedBox(height: 12),
          ZendAvatar(
            radius: 32,
            initials: (_displayName?.isNotEmpty ?? false) ? _displayName![0].toUpperCase() : '?',
            photoUrl: _avatarUrl,
          ),
          const SizedBox(height: 12),
          Text(
            _zendtag != null ? '@$_zendtag' : (_displayName ?? _email ?? ''),
            style: TextStyle(fontFamily: 'Geist', fontSize: 20, fontWeight: FontWeight.w600, color: zt.textPrimary),
          ),
          if (_email != null) ...[
            const SizedBox(height: 2),
            Text(
              _email!,
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: 'Send', onPressed: _goToSendAmount),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlineActionButton(label: 'Request', onPressed: _openRequest),
          ),
        ],
      ),
    );
  }

  Widget _buildSendAmountStage(ZendTheme zt) {
    return Padding(
      key: const ValueKey('sendAmount'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => setState(() => _stage = _EntryStage.intent),
              child: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 20, fontWeight: FontWeight.w600, color: zt.textPrimary),
          ),
          const SizedBox(height: 4),
          ZendAvatar(
            radius: 24,
            initials: (_displayName?.isNotEmpty ?? false) ? _displayName![0].toUpperCase() : '?',
            photoUrl: _avatarUrl,
          ),
          const SizedBox(height: 8),
          Text(
            _zendtag != null ? '@$_zendtag' : (_displayName ?? _email ?? ''),
            style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textSecondary),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _sendAmountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 40, fontWeight: FontWeight.w700, color: zt.textPrimary),
            decoration: InputDecoration(
              prefixText: '\$',
              prefixStyle: TextStyle(fontFamily: 'Geist', fontSize: 32, fontWeight: FontWeight.w700, color: zt.textPrimary),
              hintText: '0',
              hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 40, fontWeight: FontWeight.w700, color: zt.textSecondary),
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sendNoteController,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add a note',
              hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: (double.tryParse(_sendAmountController.text.trim()) ?? 0) > 0
                  ? 'Send \$${_sendAmountController.text.trim()}'
                  : 'Enter an amount',
              onPressed: (double.tryParse(_sendAmountController.text.trim()) ?? 0) > 0 ? _confirmSendAmount : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.displayName,
    required this.subtitle,
    required this.avatarLabel,
    required this.onTap,
    this.avatarUrl,
  });

  final String displayName;
  final String subtitle;
  final String avatarLabel;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              ZendAvatar(radius: 18, initials: avatarLabel, photoUrl: avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary)),
                    Text(subtitle, style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
