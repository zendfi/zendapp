import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/account_deletion_models.dart';
import '../../navigation/zend_routes.dart';
import '../onboarding/welcome_screen.dart';
import '../send/withdraw_sheet.dart';

/// Account deletion, required by the Google Play User Data policy for any app
/// that lets users create an account in-app.
///
/// ## Why this screen leads with the balance
///
/// Deleting the account destroys the zkLogin salt, and what that costs depends
/// on the account: for rows still on the `random` strategy the server holds the
/// only copy that exists anywhere, with no seed phrase and no provider able to
/// re-derive it. Destroying it while value sits at the address would take the
/// money with it. So the server refuses to delete a funded account, and this
/// screen asks before offering the button rather than letting the user commit
/// to something that then fails.
///
/// ## Why it admits what it cannot delete
///
/// Two things survive, and saying so is not a disclaimer — it is the difference
/// between an honest promise and one we would break:
///
///   * Transfer, pay-in, bank-send and identity-verification records, kept
///     because AML law requires it. The retention period comes from the server
///     so the number shown is the one actually applied.
///   * Anything already settled on Sui. Mainnet is immutable and public, so no
///     one can remove it, us included.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  DeletionReadiness? _readiness;
  bool _loading = true;
  String? _loadError;

  /// Explicit opt-in, so the destructive button is never the default state of
  /// the screen.
  bool _understood = false;
  bool _deleting = false;
  String? _deleteError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final model = ZendScope.read(context);
    try {
      final readiness =
          await model.walletService.apiClient.getDeletionReadiness();
      if (!mounted) return;
      setState(() {
        _readiness = readiness;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = "Couldn't check your account. Try again.";
      });
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _deleteError = null;
    });

    final model = ZendScope.read(context);
    try {
      await model.walletService.apiClient.deleteAccount();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deleteError =
            "Couldn't delete your account. Nothing was changed — try again.";
      });
      return;
    }

    // Local teardown. The server has already purged this device's push token,
    // so there is nothing to unregister; what remains is clearing the session
    // and in-memory state. `logout()` is allowed to fail — the account is
    // already gone server-side, and refusing to clear local state because a
    // courtesy call failed would leave the user staring at a dead session.
    try {
      await model.authService.logout();
    } catch (_) {
      // Intentionally ignored; resetState below is the part that matters.
    }
    model.resetState();

    if (!mounted) return;
    pushAndRemoveUntilZendSlide(
      context,
      const WelcomeScreen(),
      rootNavigator: true,
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
                    icon: Icon(
                      PhosphorIconsRegular.caretLeft,
                      color: zt.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Delete account',
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
            ),
            Expanded(child: _body(zt)),
          ],
        ),
      ),
    );
  }

  Widget _body(ZendTheme zt) {
    if (_loading) {
      return const Center(child: ZendLoader());
    }
    if (_loadError != null) {
      return ZendErrorState(title: _loadError!, onRetry: _load);
    }

    final readiness = _readiness;
    if (readiness == null) {
      return const SizedBox.shrink();
    }

    if (readiness.blockedByBalance) {
      return _BlockedByBalance(readiness: readiness, onWithdrawn: _load);
    }
    if (readiness.blockedByPendingTransfers) {
      return _BlockedByPending(readiness: readiness, onRecheck: _load);
    }
    return _ReadyToDelete(
      readiness: readiness,
      understood: _understood,
      onUnderstoodChanged: (v) => setState(() => _understood = v),
      deleting: _deleting,
      error: _deleteError,
      onDelete: _delete,
    );
  }
}

// ── Blocked: wallet still holds money ────────────────────────────────────────

class _BlockedByBalance extends StatelessWidget {
  const _BlockedByBalance({required this.readiness, required this.onWithdrawn});

  final DeletionReadiness readiness;
  final Future<void> Function() onWithdrawn;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final funded = readiness.holdings
        .where((h) => h.usdcBalance > 0)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading('Withdraw your money first', zt: zt),
          const SizedBox(height: 12),
          _Body(
            'Deleting your account permanently destroys the key to your '
            'wallet. If you delete while money is still in it, that money '
            'cannot be recovered by anyone — including us.',
            zt: zt,
          ),
          const SizedBox(height: 24),
          for (final holding in funded) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: zt.bgCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${holding.railLabel} wallet',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        color: zt.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '\$${holding.usdcBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          _PrimaryButton(
            label: 'Withdraw',
            onTap: () async {
              await showWithdrawSheet(context);
              // Re-check rather than assume: the sheet can be dismissed
              // without withdrawing, and a partial withdrawal still blocks.
              await onWithdrawn();
            },
            zt: zt,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => onWithdrawn(),
              style: TextButton.styleFrom(foregroundColor: zt.textSecondary),
              child: const Text(
                'I’ve withdrawn — check again',
                style: TextStyle(fontFamily: 'Geist', fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Blocked: transfers still in flight ───────────────────────────────────────

class _BlockedByPending extends StatelessWidget {
  const _BlockedByPending({required this.readiness, required this.onRecheck});

  final DeletionReadiness readiness;
  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final count = readiness.pendingTransferCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading('You have money in flight', zt: zt),
          const SizedBox(height: 12),
          _Body(
            count == 1
                ? 'One transfer you sent hasn’t been claimed yet. If it '
                      'expires after your account is gone, the refund would '
                      'have nowhere to go.'
                : '$count transfers you sent haven’t been claimed yet. If they '
                      'expire after your account is gone, the refunds would '
                      'have nowhere to go.',
            zt: zt,
          ),
          const SizedBox(height: 12),
          _Body(
            'Wait for them to be claimed or to expire, then come back.',
            zt: zt,
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Check again', onTap: onRecheck, zt: zt),
        ],
      ),
    );
  }
}

// ── Ready ────────────────────────────────────────────────────────────────────

class _ReadyToDelete extends StatelessWidget {
  const _ReadyToDelete({
    required this.readiness,
    required this.understood,
    required this.onUnderstoodChanged,
    required this.deleting,
    required this.error,
    required this.onDelete,
  });

  final DeletionReadiness readiness;
  final bool understood;
  final ValueChanged<bool> onUnderstoodChanged;
  final bool deleting;
  final String? error;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final years = readiness.retentionYears;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading('This cannot be undone', zt: zt),
          const SizedBox(height: 16),

          _Section(
            title: 'What gets deleted',
            lines: const [
              'Your profile, handle and photo',
              'Your messages and conversations',
              'Who you’re connected to',
              'Your saved banks and payment requests',
              'Your wallet keys and sign-in details',
            ],
            zt: zt,
          ),
          const SizedBox(height: 20),

          _Section(
            title: 'What we have to keep',
            lines: [
              if (years > 0)
                'Records of money you sent or received, and your identity '
                    'verification, for $years years'
              else
                'Records of money you sent or received, and your identity '
                    'verification',
              'Required by anti-money-laundering law. These are not used for '
                  'anything else.',
            ],
            zt: zt,
          ),
          const SizedBox(height: 20),

          _Section(
            title: 'What nobody can delete',
            lines: const [
              'Payments already settled on the Sui blockchain stay public and '
                  'permanent. That is how the blockchain works — we cannot '
                  'remove them, and neither can anyone else.',
            ],
            zt: zt,
          ),
          const SizedBox(height: 28),

          InkWell(
            onTap: deleting ? null : () => onUnderstoodChanged(!understood),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: understood,
                    onChanged: deleting
                        ? null
                        : (v) => onUnderstoodChanged(v ?? false),
                    activeColor: zt.destructive,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'I understand my account and data will be permanently '
                        'deleted.',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 15,
                          height: 1.4,
                          color: zt.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 14),
            Text(
              error!,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                color: zt.destructive,
              ),
            ),
          ],

          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'Delete my account',
            // Disabled until explicitly acknowledged, so the irreversible
            // action is never one stray tap away on arrival.
            onTap: understood && !deleting ? onDelete : null,
            destructive: true,
            busy: deleting,
            zt: zt,
          ),
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.zt});
  final String text;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Geist',
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: zt.textPrimary,
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {required this.zt});
  final String text;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Geist',
      fontSize: 15,
      height: 1.5,
      color: zt.textSecondary,
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines, required this.zt});
  final String title;
  final List<String> lines;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 15,
                height: 1.45,
                color: zt.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.zt,
    this.destructive = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final ZendTheme zt;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final bg = destructive ? zt.destructive : zt.accent;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
