import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../design/zend_verified_badge.dart';
import '../../models/api_exceptions.dart';

/// Runs the passport scan on the phone and returns the result for the server to check, or null if
/// the person backed out. Set by the app once a scanner is integrated; until then the screen says
/// scanning isn't in this version, and never starts a check it can't finish.
abstract class HumanCheckLauncher {
  bool get isAvailable;
  Future<Map<String, dynamic>?> scan({required String nonce});
}

HumanCheckLauncher? humanCheckLauncher;

/// Debug builds only: asks for a made-up passport id instead of scanning one. It lets the whole
/// flow be tried against the stub verifier (`scripts/human-badge-stub-verifier.mjs`). A release
/// build never uses it, and a real verifier would refuse its result anyway.
class _DebugHumanCheckLauncher implements HumanCheckLauncher {
  _DebugHumanCheckLauncher(this.context);
  final BuildContext context;

  @override
  bool get isAvailable => true;

  @override
  Future<Map<String, dynamic>?> scan({required String nonce}) async {
    final ctrl = TextEditingController(text: 'test-passport-1');
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test passport id (debug only)'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty) return null;
    return {'test_id': id};
  }
}

/// "Verify you're a real person". Shows where the person stands and, when allowed, starts a check.
class HumanVerificationScreen extends StatefulWidget {
  const HumanVerificationScreen({super.key});

  @override
  State<HumanVerificationScreen> createState() =>
      _HumanVerificationScreenState();
}

class _HumanVerificationScreenState extends State<HumanVerificationScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  HumanCheckLauncher? get _launcher =>
      humanCheckLauncher ??
      (kDebugMode ? _DebugHumanCheckLauncher(context) : null);

  Future<void> _load() async {
    final api = ZendScope.read(context).walletService.apiClient;
    try {
      final s = await api.getHumanVerification();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    final launcher = _launcher;
    if (launcher == null || !launcher.isAvailable || _working) return;
    final api = ZendScope.read(context).walletService.apiClient;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final challenge = await api.startHumanCheck();
      final result = await launcher.scan(nonce: challenge['nonce'] as String);
      if (result == null) return; // backed out
      final s = await api.completeHumanCheck(
        challengeId: challenge['challenge_id'] as String,
        nonce: challenge['nonce'] as String,
        result: result,
      );
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _reasonCopy(String? reason) => switch (reason) {
    'name_changed' => 'You changed your name.',
    'handle_changed' => 'You changed your @handle.',
    'photo_changed' => 'You changed your photo.',
    'bio_changed' => 'You changed your bio.',
    'moderation' => 'Your badge was removed after a report.',
    'account_recovery' => 'Your account was recovered.',
    _ => '',
  };

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final status = _status?['status'] as String? ?? 'none';
    final reason = _reasonCopy(_status?['reason'] as String?);
    final available = _status?['available'] == true;
    final launcher = _launcher;
    final canScan = !kIsWeb && launcher != null && launcher.isAvailable;

    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
          height: 1.35,
        );

    final (String headline, String body) = switch (status) {
      'active' => (
        'You\'re verified',
        'A check mark shows next to your name. It is valid until ${_date(_status?['expires_at'] as String?)}.',
      ),
      'needs_recheck' => (
        'Check again to bring back your badge',
        '${reason.isEmpty ? '' : '$reason '}Your check mark is hidden until you check again. It takes a minute.',
      ),
      'expired' => (
        'Your badge expired',
        'Check again to bring back the check mark next to your name.',
      ),
      'revoked' => (
        'Your badge was removed',
        '${reason.isEmpty ? '' : '$reason '}You can check again to earn it back.',
      ),
      _ => (
        'Show you\'re a real person',
        'Scan your passport to get a check mark next to your name. Your passport details stay on your phone. Zend never sees them.',
      ),
    };

    final needsAction = status != 'active';
    final String? blocker = !available
        ? 'This isn\'t available yet.'
        : kIsWeb
        ? 'Open the Zend app on your phone to verify.'
        : !canScan
        ? 'Passport scanning is coming to this version soon.'
        : null;

    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(
        backgroundColor: zt.bgPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: zt.textPrimary),
        title: Text(
          'Verify you\'re a real person',
          style: s(17, w: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: ZendLoader(size: 22))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: zt.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: status == 'active'
                        ? const VerifiedBadge(size: 40)
                        : Icon(
                            PhosphorIconsRegular.identificationBadge,
                            size: 34,
                            color: zt.accent,
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: s(20, w: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: s(14, c: zt.textSecondary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: s(13, c: zt.destructive),
                  ),
                ],
                const SizedBox(height: 24),
                if (needsAction) ...[
                  PrimaryButton(
                    label: status == 'none' ? 'Start check' : 'Check again',
                    isLoading: _working,
                    onPressed: blocker == null && !_working ? _start : null,
                  ),
                  if (blocker != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      blocker,
                      textAlign: TextAlign.center,
                      style: s(12.5, c: zt.textSecondary),
                    ),
                  ],
                ],
                const SizedBox(height: 28),
                Text(
                  'A check mark means a real person controls this account. It doesn\'t show your name or any ID details. If you change your name, @handle, photo or bio, the check mark is hidden until you check again.',
                  textAlign: TextAlign.center,
                  style: s(12, c: zt.textSecondary),
                ),
              ],
            ),
    );
  }
}
