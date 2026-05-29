import 'dart:async';

import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../core/zend_state.dart';
import '../../navigation/zend_routes.dart';
import 'success_screen.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool? _available;

  bool _showingReservedBadge = false;

  @override
  void initState() {
    super.initState();
    final model = ZendScope.of(context);
    final reserved = model.pendingReservedZendtag;
    if (reserved != null && reserved.isNotEmpty) {
      _controller.text = reserved;
      _showingReservedBadge = true;
      _available = true;
      model.setUsername(reserved);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleCheck(String value) {
    _debounce?.cancel();
    setState(() {
      _available = null;
      _showingReservedBadge = false;
    });

    final tag = value.trim().toLowerCase();
    if (tag.isEmpty || tag.length < 3) return;
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(tag)) return;
    if (tag.startsWith('.') || tag.startsWith('_') || tag.endsWith('.') || tag.endsWith('_')) return;

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final model = ZendScope.of(context);
        final isAvailable = await model.zendtagService.checkAvailability(tag);
        if (!mounted) return;
        setState(() => _available = isAvailable);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final username = _controller.text.trim().isEmpty ? '' : _controller.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: ZendScrollPage(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      _showingReservedBadge ? 'Your @, as you reserved it.' : 'Choose your @',
                      style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                    if (_showingReservedBadge) ...[
                      const SizedBox(height: 6),
                      Text(
                        "We held it for you. Keep it, or pick a different one.",
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_showingReservedBadge) ...[
                      Text('RESERVED FOR YOU', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, letterSpacing: 1.8, color: zt.textSecondary)),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('@', style: TextStyle(fontFamily: 'DMMono', color: zt.textSecondary, fontSize: 18)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onChanged: (value) {
                              _scheduleCheck(value);
                              model.setUsername(value);
                            },
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 20, color: zt.textPrimary),
                            decoration: InputDecoration(
                              filled: false,
                              border: UnderlineInputBorder(borderSide: BorderSide(color: zt.border)),
                              hintText: 'yourname',
                              hintStyle: TextStyle(color: zt.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _available == null
                              ? const SizedBox(width: 28, height: 28)
                              : Text(
                                  _available! ? '✓' : '✗',
                                  key: ValueKey<bool>(_available!),
                                  style: TextStyle(color: _available! ? ZendColors.positive : ZendColors.destructive, fontSize: 24),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _PreviewCard(username: username),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Continue',
                      // Skip KYC — go directly to SuccessScreen
                      onPressed: () => pushZendSlide(context, SuccessScreen(username: model.username)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final safeUsername = username.isEmpty ? 'yourname' : username;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: zt.bgCard, borderRadius: BorderRadius.circular(ZendRadii.sm)),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.alternate_email, color: zt.textSecondary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Zend Link', style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textPrimary)),
              const SizedBox(height: 2),
              Text('zdfi.me/', style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.textSecondary)),
              Text(safeUsername, style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.textPrimary)),
            ],
          ),
          const Spacer(),
          Container(
            width: 34, height: 34,
            decoration: const BoxDecoration(color: ZendColors.accentPop, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 18, color: ZendColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

