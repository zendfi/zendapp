import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/recent_contact.dart';
import 'pool.dart';
import 'pool_detail_screen.dart';

Future<void> showCreatePoolDrawer(
  BuildContext context, {
  required double targetAmount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1.0,
      child: CreatePoolDrawer(targetAmount: targetAmount),
    ),
  );
}

class CreatePoolDrawer extends StatefulWidget {
  const CreatePoolDrawer({super.key, required this.targetAmount});

  final double targetAmount;

  @override
  State<CreatePoolDrawer> createState() => _CreatePoolDrawerState();
}

List<PoolParticipant> _buildRecentPoolContacts(
  List<RecentContact> contacts,
) {
  return contacts.take(5).map((c) => PoolParticipant(
    id: '',
    displayName: c.name,
    avatarLabel: c.avatarLabel,
    zendtag: c.tag,  // carry the zendtag so the API payload is correct
    isExternal: false,
  )).toList();
}

class _CreatePoolDrawerState extends State<CreatePoolDrawer> {
  static const int _nameMaxLength = 50;

  // Initialized in initState because they depend on widget.targetAmount
  late double _targetAmount;
  late final TextEditingController _amountController;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _zendUserController = TextEditingController();
  final TextEditingController _externalContactController =
      TextEditingController();

  final List<PoolParticipant> _participants = [];
  DateTime? _deadline;

  String? _nameError;
  String? _amountError;
  String? _participantError;
  String? _deadlineError;

  @override
  void initState() {
    super.initState();
    _targetAmount = widget.targetAmount;
    _amountController = TextEditingController(
      text: widget.targetAmount > 0 ? widget.targetAmount.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _zendUserController.dispose();
    _externalContactController.dispose();
    super.dispose();
  }

  Future<void> _addZendUser(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    final normalized = trimmed.toLowerCase();
    final searchTag = normalized.startsWith('@')
        ? normalized.substring(1)
        : normalized;

    if (searchTag.length < 3) {
      setState(() {
        _participantError = 'Username must be at least 3 characters';
      });
      return;
    }

    try {
      final model = ZendScope.of(context);
      final resolved = await model.zendtagService.resolve(searchTag);

      final displayName = resolved.displayName.trim().isEmpty
          ? '@${resolved.zendtag}'
          : resolved.displayName;
      final avatarLabel = displayName.isNotEmpty
          ? displayName[0].toUpperCase()
          : resolved.zendtag.isNotEmpty
              ? resolved.zendtag[0].toUpperCase()
              : '?';

      setState(() {
        _participants.add(PoolParticipant(
          id: '',
          displayName: displayName,
          avatarLabel: avatarLabel,
          zendtag: resolved.zendtag,  // store the resolved zendtag
          isExternal: false,
        ));
        _participantError = null;
        _zendUserController.clear();
      });
    } catch (e) {
      setState(() {
        _participantError = 'User not found';
      });
    }
  }

  void _addExternalContact(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _participants.add(PoolParticipant(
        id: '',
        displayName: trimmed,
        avatarLabel: trimmed[0].toUpperCase(),
        isExternal: true,
      ));
      _participantError = null;
      _externalContactController.clear();
    });
  }

  void _removeParticipant(int index) {
    setState(() {
      _participants.removeAt(index);
    });
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null) {
      if (picked.isBefore(DateTime.now())) {
        setState(() {
          _deadlineError = 'Please select a future date';
        });
      } else {
        setState(() {
          _deadline = picked;
          _deadlineError = null;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  bool _creating = false;
  String? _createError;

  void _onCreatePool() async {
    final trimmedName = _nameController.text.trim();
    bool hasError = false;

    if (trimmedName.isEmpty) {
      setState(() => _nameError = 'Enter a pool name');
      hasError = true;
    } else {
      setState(() => _nameError = null);
    }

    final parsedAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (parsedAmount < 0.01) {
      setState(() => _amountError = 'Enter a valid amount');
      hasError = true;
    } else {
      setState(() {
        _targetAmount = parsedAmount;
        _amountError = null;
      });
    }

    if (_participants.isEmpty) {
      setState(() => _participantError = 'Add at least one participant');
      hasError = true;
    } else {
      setState(() => _participantError = null);
    }

    if (hasError) return;

    setState(() {
      _creating = true;
      _createError = null;
    });

    try {
      final model = ZendScope.of(context);

      // Build participant payload for the API
      final participantPayload = <Map<String, dynamic>>[];
      for (final p in _participants) {
        String? paymentRequestId;

        if (p.isExternal) {
          // Generate a payment request link for external contacts
          try {
            final requestData = await model.walletService.apiClient
                .createPaymentRequest(
              amountUsdc: _targetAmount,
              description: 'Pool: $trimmedName — ${p.displayName}',
            );
            paymentRequestId = requestData['id'] as String?;
          } catch (_) {
            // Non-fatal — pool can still be created without the link
          }
        }

        participantPayload.add({
          'display_name': p.displayName,
          'is_external': p.isExternal,
          // Use the stored zendtag (set when user was resolved via search or
          // selected from recent contacts). Falls back to stripping '@' from
          // display name for legacy entries.
          if (p.zendtag != null && p.zendtag!.isNotEmpty)
            'zendtag': p.zendtag,
          'payment_request_id': paymentRequestId,
        });
      }

      // Create pool via API
      final pool = await model.walletService.apiClient.createPool(
        name: trimmedName,
        targetAmountUsdc: _targetAmount,
        deadline: _deadline,
        participants: participantPayload,
      );

      // Add to local cache
      model.addPool(pool);

      if (!mounted) return;

      // Navigate to the new pool's detail screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PoolDetailScreen(pool: pool),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _createError = 'Failed to create pool. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final recentContacts = _buildRecentPoolContacts(model.recentContacts);
    final nameRemaining = _nameMaxLength - _nameController.text.length;

    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ZendScrollPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ZendSheetHandle(),
              const SizedBox(height: ZendSpacing.lg),

              Text(
                'Create a pool',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xl),

              // Amount input — editable
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Goal amount',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 36,
                      fontStyle: FontStyle.italic,
                      color: zt.textPrimary,
                    ),
                    decoration: InputDecoration(
                      prefixText: '\$',
                      prefixStyle: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 24,
                        color: zt.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      hintText: '0.00',
                      hintStyle: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 36,
                        fontStyle: FontStyle.italic,
                        color: zt.textSecondary.withValues(alpha: 0.4),
                      ),
                      errorText: _amountError,
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: zt.border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: zt.accentBright, width: 2),
                      ),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v) ?? 0.0;
                      if (parsed > 0 && _amountError != null) {
                        setState(() => _amountError = null);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: ZendSpacing.lg),

              TextField(
                controller: _nameController,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_nameMaxLength),
                ],
                onChanged: (_) => setState(() {
                  if (_nameError != null) _nameError = null;
                }),
                decoration: InputDecoration(
                  hintText: 'Pool name',
                  hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textSecondary),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textPrimary),
              ),
              const SizedBox(height: ZendSpacing.xxs),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$nameRemaining remaining',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: nameRemaining < 10 ? ZendColors.destructive : zt.textSecondary,
                  ),
                ),
              ),
              if (_nameError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(_nameError!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: ZendColors.destructive)),
              ],
              const SizedBox(height: ZendSpacing.md),

              Text(
                'Add participants',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary),
              ),
              const SizedBox(height: ZendSpacing.xs),

              _SectionLabel('Recent Zend users'),
              const SizedBox(height: ZendSpacing.xxs),
              if (recentContacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No recent Zend users yet',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary),
                  ),
                )
              else
                ...recentContacts.map((contact) {
                  final isSelected = _participants.any(
                    (p) => p.displayName == contact.displayName && !p.isExternal,
                  );
                  return _SelectableContactTile(
                    participant: contact,
                    selected: isSelected,
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _participants.removeWhere(
                            (p) => p.displayName == contact.displayName && !p.isExternal,
                          );
                        } else {
                          _participants.add(contact);
                          _participantError = null;
                        }
                      });
                    },
                  );
                }),
              const SizedBox(height: ZendSpacing.xs),

              TextField(
                controller: _zendUserController,
                textInputAction: TextInputAction.done,
                onSubmitted: _addZendUser,
                decoration: InputDecoration(
                  hintText: 'Add @username',
                  hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                  prefixIcon: Icon(Icons.person_add_outlined, size: 18, color: zt.textSecondary),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
              ),
              const SizedBox(height: ZendSpacing.md),

              _SectionLabel('Invite via email or phone'),
              const SizedBox(height: ZendSpacing.xxs),
              TextField(
                controller: _externalContactController,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: _addExternalContact,
                decoration: InputDecoration(
                  hintText: 'Email or phone number',
                  hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                  prefixIcon: Icon(Icons.mail_outline, size: 18, color: zt.textSecondary),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
              ),
              const SizedBox(height: ZendSpacing.xs),

              if (_participants.isNotEmpty) ...[
                Wrap(
                  spacing: ZendSpacing.xs,
                  runSpacing: ZendSpacing.xs,
                  children: List.generate(_participants.length, (index) {
                    final p = _participants[index];
                    return Chip(
                      avatar: CircleAvatar(
                        radius: 12,
                        backgroundColor: p.isExternal ? zt.bgSecondary : zt.accent,
                        child: Text(
                          p.avatarLabel,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: p.isExternal ? zt.textPrimary : ZendColors.textOnDeep,
                          ),
                        ),
                      ),
                      label: Text(
                        p.displayName,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textPrimary),
                      ),
                      deleteIcon: Icon(Icons.close, size: 16, color: zt.textSecondary),
                      onDeleted: () => _removeParticipant(index),
                      backgroundColor: p.isExternal
                          ? zt.bgSecondary
                          : zt.accentPop.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                        side: BorderSide(
                          color: p.isExternal
                              ? zt.border
                              : zt.accentBright.withValues(alpha: 0.3),
                        ),
                      ),
                    );
                  }),
                ),
              ],
              if (_participantError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(_participantError!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: ZendColors.destructive)),
              ],
              const SizedBox(height: ZendSpacing.md),

              _TappableRow(
                label: _deadline != null
                    ? 'Deadline: ${_formatDate(_deadline!)}'
                    : 'Set deadline',
                trailing: Icon(Icons.chevron_right, size: 18, color: zt.textSecondary),
                onTap: _pickDeadline,
              ),
              if (_deadlineError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(_deadlineError!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: ZendColors.destructive)),
              ],

              const SizedBox(height: ZendSpacing.xxl),
              const Spacer(),

              if (_createError != null) ...[
                Text(_createError!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.destructive)),
                const SizedBox(height: ZendSpacing.xs),
              ],

              PrimaryButton(
                label: _creating ? 'Creating...' : 'Create pool',
                onPressed: _creating ? null : _onCreatePool,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TappableRow extends StatelessWidget {
  const _TappableRow({required this.label, required this.trailing, required this.onTap});
  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(ZendRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.md, vertical: ZendSpacing.sm),
        decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.sm)),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textPrimary))),
            trailing,
          ],
        ),
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
    return Text(
      label.toUpperCase(),
      style: TextStyle(fontFamily: 'DMSans', fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: zt.textSecondary),
    );
  }
}

class _SelectableContactTile extends StatelessWidget {
  const _SelectableContactTile({required this.participant, required this.selected, required this.onTap});
  final PoolParticipant participant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? zt.accentPop.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(ZendRadii.sm),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: selected ? zt.accent : zt.bgSecondary,
              child: Text(
                participant.avatarLabel,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w600, color: selected ? ZendColors.textOnDeep : zt.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(participant.displayName, style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary))),
            if (selected) Icon(Icons.check_circle, size: 20, color: zt.accentBright),
          ],
        ),
      ),
    );
  }
}
