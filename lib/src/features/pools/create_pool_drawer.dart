import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../request/payment_request.dart';
import '../request/request_utils.dart';
import 'pool.dart';
import 'pool_detail_screen.dart';

Future<void> showCreatePoolDrawer(
  BuildContext context, {
  required double targetAmount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
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
  List<ZendTransaction> transactions,
) {
  final seen = <String>{};
  final contacts = <PoolParticipant>[];

  for (final tx in transactions) {
    final raw = tx.name.trim();
    final tag = raw.startsWith('@') ? raw.substring(1) : raw;
    if (tag.isEmpty || seen.contains(tag)) continue;
    seen.add(tag);
    contacts.add(PoolParticipant(
      displayName: raw.isEmpty ? '@$tag' : raw,
      avatarLabel: tx.avatarLabel,
      isExternal: false,
    ));
  }

  return contacts;
}

class _CreatePoolDrawerState extends State<CreatePoolDrawer> {
  static const int _nameMaxLength = 50;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _zendUserController = TextEditingController();
  final TextEditingController _externalContactController =
      TextEditingController();

  final List<PoolParticipant> _participants = [];
  DateTime? _deadline;

  String? _nameError;
  String? _participantError;
  String? _deadlineError;

  @override
  void dispose() {
    _nameController.dispose();
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
          displayName: displayName,
          avatarLabel: avatarLabel,
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

  void _onCreatePool() {
    final trimmedName = _nameController.text.trim();
    bool hasError = false;

    if (trimmedName.isEmpty) {
      setState(() => _nameError = 'Enter a pool name');
      hasError = true;
    } else {
      setState(() => _nameError = null);
    }

    if (_participants.isEmpty) {
      setState(() => _participantError = 'Add at least one participant');
      hasError = true;
    } else {
      setState(() => _participantError = null);
    }

    if (hasError) return;

    final model = ZendScope.of(context);
    final poolId = generatePoolId();

    final pool = Pool(
      id: poolId,
      name: trimmedName,
      targetAmount: widget.targetAmount,
      participants: List.of(_participants),
      createdAt: DateTime.now(),
      deadline: _deadline,
      gathered: 0.0,
      status: PoolStatus.active,
    );

    // Generate payment request links for external contacts
    for (final participant in _participants) {
      if (participant.isExternal) {
        final requestId = generateRequestId();
        final link = buildRequestLink(model.username, requestId);
        final request = PaymentRequest(
          id: requestId,
          link: link,
          amount: widget.targetAmount,
          description: 'Pool: $trimmedName — ${participant.displayName}',
          createdAt: DateTime.now(),
          status: PaymentRequestStatus.pending,
        );
        model.addPaymentRequest(request);
      }
    }

    model.addPool(pool);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PoolDetailScreen(pool: pool),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final recentContacts = _buildRecentPoolContacts(model.recentTransactions);
    final nameRemaining = _nameMaxLength - _nameController.text.length;

    return Container(
      decoration: const BoxDecoration(
        color: ZendColors.bgPrimary,
        borderRadius: BorderRadius.vertical(
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

              // ── Title ──
              const Text(
                'Create a pool',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: ZendColors.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xl),

              // ── Target amount (read-only) ──
              Text(
                formatRequestAmount(widget.targetAmount),
                style: const TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  color: ZendColors.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.lg),

              // ── Pool name field ──
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
                  hintStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: ZendColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: ZendColors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: ZendColors.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xxs),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$nameRemaining remaining',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: nameRemaining < 10
                        ? ZendColors.destructive
                        : ZendColors.textSecondary,
                  ),
                ),
              ),
              if (_nameError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(
                  _nameError!,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
              ],
              const SizedBox(height: ZendSpacing.md),

              // ── Add participants section ──
              const Text(
                'Add participants',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ZendColors.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xs),

              // Known Zend contacts — tap to toggle selection
              _SectionLabel('Recent Zend users'),
              const SizedBox(height: ZendSpacing.xxs),
              if (recentContacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No recent Zend users yet',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: ZendColors.textSecondary,
                    ),
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

              // Add new Zend user by username
              TextField(
                controller: _zendUserController,
                textInputAction: TextInputAction.done,
                onSubmitted: _addZendUser,
                decoration: InputDecoration(
                  hintText: 'Add @username',
                  hintStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: ZendColors.textSecondary,
                  ),
                  prefixIcon: const Icon(Icons.person_add_outlined, size: 18, color: ZendColors.textSecondary),
                  filled: true,
                  fillColor: ZendColors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: ZendColors.textPrimary),
              ),
              const SizedBox(height: ZendSpacing.md),

              // External contact via email or phone
              _SectionLabel('Invite via email or phone'),
              const SizedBox(height: ZendSpacing.xxs),
              TextField(
                controller: _externalContactController,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: _addExternalContact,
                decoration: InputDecoration(
                  hintText: 'Email or phone number',
                  hintStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: ZendColors.textSecondary,
                  ),
                  prefixIcon: const Icon(Icons.mail_outline, size: 18, color: ZendColors.textSecondary),
                  filled: true,
                  fillColor: ZendColors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: ZendColors.textPrimary),
              ),
              const SizedBox(height: ZendSpacing.xs),

              // Selected participant chips
              if (_participants.isNotEmpty) ...[
                Wrap(
                  spacing: ZendSpacing.xs,
                  runSpacing: ZendSpacing.xs,
                  children: List.generate(_participants.length, (index) {
                    final p = _participants[index];
                    return Chip(
                      avatar: CircleAvatar(
                        radius: 12,
                        backgroundColor: p.isExternal
                            ? ZendColors.bgSecondary
                            : ZendColors.accent,
                        child: Text(
                          p.avatarLabel,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: p.isExternal
                                ? ZendColors.textPrimary
                                : ZendColors.textOnDeep,
                          ),
                        ),
                      ),
                      label: Text(
                        p.displayName,
                        style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.textPrimary,
                        ),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => _removeParticipant(index),
                      backgroundColor: p.isExternal
                          ? ZendColors.bgSecondary
                          : ZendColors.accentPop.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                        side: BorderSide(
                          color: p.isExternal
                              ? ZendColors.border
                              : ZendColors.accentBright.withValues(alpha: 0.3),
                        ),
                      ),
                    );
                  }),
                ),
              ],
              if (_participantError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(
                  _participantError!,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
              ],
              const SizedBox(height: ZendSpacing.md),

              // ── Set deadline row ──
              _TappableRow(
                label: _deadline != null
                    ? 'Deadline: ${_formatDate(_deadline!)}'
                    : 'Set deadline',
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: ZendColors.textSecondary,
                ),
                onTap: _pickDeadline,
              ),
              if (_deadlineError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(
                  _deadlineError!,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
              ],

              // ── Spacer to push button to bottom ──
              const SizedBox(height: ZendSpacing.xxl),
              const Spacer(),

              // ── Create pool button ──
              PrimaryButton(
                label: 'Create pool',
                onPressed: _onCreatePool,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TappableRow extends StatelessWidget {
  const _TappableRow({
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ZendRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZendSpacing.md,
          vertical: ZendSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: ZendColors.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: ZendColors.textPrimary,
                ),
              ),
            ),
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
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: ZendColors.textSecondary,
      ),
    );
  }
}

class _SelectableContactTile extends StatelessWidget {
  const _SelectableContactTile({
    required this.participant,
    required this.selected,
    required this.onTap,
  });

  final PoolParticipant participant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? ZendColors.accentPop.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(ZendRadii.sm),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: selected ? ZendColors.accent : ZendColors.bgSecondary,
              child: Text(
                participant.avatarLabel,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? ZendColors.textOnDeep : ZendColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                participant.displayName,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: ZendColors.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 20, color: ZendColors.accentBright),
          ],
        ),
      ),
    );
  }
}
