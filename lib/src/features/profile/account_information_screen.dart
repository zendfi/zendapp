import 'package:flutter/material.dart';
import '../../models/api_exceptions.dart' show friendlyError;
import '../../core/zend_format.dart';
import '../onboarding/zendtag_prompt_sheet.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../models/handle_label.dart';

class AccountInformationScreen extends StatefulWidget {
  const AccountInformationScreen({super.key});

  @override
  State<AccountInformationScreen> createState() =>
      _AccountInformationScreenState();
}

class _AccountInformationScreenState extends State<AccountInformationScreen> {
  Map<String, dynamic>? _change; // zendtag change status
  String? _birthdate; // YYYY-MM-DD
  String? _phone;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = ZendScope.read(context).walletService.apiClient;
    try {
      final r = await Future.wait([
        api.getZendtagChangeStatus(),
        api.getProfileDetails(),
      ]);
      if (!mounted) return;
      setState(() {
        _change = r[0];
        _birthdate = r[1]['birthdate'] as String?;
        _phone = r[1]['phone'] as String?;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save({String? birthdate, String? phone}) async {
    final api = ZendScope.read(context).walletService.apiClient;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await api.putProfileDetails(birthdate: birthdate, phone: phone);
      if (!mounted) return;
      setState(() {
        _birthdate = r['birthdate'] as String?;
        _phone = r['phone'] as String?;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final initial =
        DateTime.tryParse(_birthdate ?? '') ??
        DateTime(now.year - 25, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Birthdate (optional)',
    );
    if (d == null) return;
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _save(birthdate: iso, phone: _phone);
  }

  Future<void> _editPhone() async {
    final ctrl = TextEditingController(text: _phone ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Phone'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '+234 801 234 5678',
            helperText: 'Include your country code',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await _save(birthdate: _birthdate, phone: value.isEmpty ? null : value);
  }

  String _formatBirthdate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : formatDate(d, now: DateTime(0));
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final zt = ZendTheme.of(context);
    final displayName = (model.currentDisplayName?.trim().isNotEmpty ?? false)
        ? model.currentDisplayName!
        : (model.username.isNotEmpty ? model.username : 'Zend User');
    // A zkLogin account starts on a placeholder (its email) until a tag is
    // chosen; don't present that as the tag.
    final placeholder = model.zendtagIsPlaceholder || model.username.isEmpty;
    final zendtag = placeholder
        ? 'Not chosen yet'
        : handleLabel(model.username);

    final canChange = _change?['can_change'] == true;
    final left = (_change?['changes_left'] as num?)?.toInt();
    final nextAt = DateTime.tryParse(
      _change?['next_change_at'] as String? ?? '',
    );
    final changeHint = left == null
        ? null
        : left == 0
        ? "You've used both Zend tag changes."
        : nextAt != null
        ? 'You can change it again on ${formatDate(nextAt)}.'
        : '$left change${left == 1 ? '' : 's'} left.';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(title: 'Account information'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('Your details'),
                    const SizedBox(height: 8),
                    _InfoGroup(
                      rows: [
                        _InfoRow(label: 'Full name', value: displayName),
                        _InfoRow(
                          label: 'Zend tag',
                          value: zendtag,
                          action: placeholder
                              ? 'Choose'
                              : canChange
                              ? 'Change'
                              : null,
                          onTap: placeholder
                              ? () => showZendtagPromptSheet(context)
                              : canChange
                              ? () => showZendtagPromptSheet(
                                  context,
                                  change: true,
                                ).then((_) => _load())
                              : null,
                        ),
                      ],
                    ),
                    if (!placeholder && changeHint != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          changeHint,
                          style: ZendTextStyles.caption.copyWith(
                            color: zt.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (placeholder) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Your Zend tag is how people find and pay you.',
                          style: ZendTextStyles.caption.copyWith(
                            color: zt.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _SectionLabel('More about you'),
                    const SizedBox(height: 8),
                    _InfoGroup(
                      rows: [
                        _InfoRow(
                          label: 'Birthdate',
                          value: !_loaded
                              ? '…'
                              : _birthdate == null
                              ? 'Optional'
                              : _formatBirthdate(_birthdate!),
                          action: _birthdate == null ? 'Add' : 'Edit',
                          onTap: _loaded ? _pickBirthdate : null,
                        ),
                        _InfoRow(
                          label: 'Phone',
                          value: !_loaded ? '…' : (_phone ?? 'Optional'),
                          action: _phone == null ? 'Add' : 'Edit',
                          onTap: _loaded ? _editPhone : null,
                        ),
                        _InfoRow(
                          label: 'Email',
                          value: model.currentUserId != null
                              ? 'On file'
                              : 'Not set',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Only you can see these.',
                        style: ZendTextStyles.caption.copyWith(
                          color: zt.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.rows});
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: ColoredBox(
        color: zt.bgSecondary,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                Divider(height: 1, thickness: 1, color: zt.border, indent: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.action,
    this.onTap,
  });

  final String label;
  final String value;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: zt.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: ZendTextStyles.tabularNumeric.copyWith(
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: row),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                action!,
                style: ZendTextStyles.caption.copyWith(
                  color: zt.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared header used by all profile sub-screens ─────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: zt.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}
