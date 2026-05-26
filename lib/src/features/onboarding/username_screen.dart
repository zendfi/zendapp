import 'dart:async';

import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../core/zend_state.dart';
import '../../navigation/zend_routes.dart';
import 'kyc_screen.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool? _available;

  /// True when the input currently holds the reserved zendtag from
  /// the waitlist (i.e. nothing's been typed over it). Drives the
  /// "RESERVED FOR YOU" eyebrow above the input — we hide it the
  /// moment the user starts editing so the chrome doesn't lie.
  bool _showingReservedBadge = false;

  @override
  void initState() {
    super.initState();

    // Prefill the input with the waitlist-reserved zendtag, if any.
    // The tag is already lowercased and validated server-side; we
    // also treat a still-available reservation as "available" so
    // Continue is unblocked immediately on first paint without
    // waiting for the debounced check to round-trip.
    final model = ZendScope.of(context);
    final reserved = model.pendingReservedZendtag;
    if (reserved != null && reserved.isNotEmpty) {
      _controller.text = reserved;
      _showingReservedBadge = true;
      _available = true;
      // Mirror into the model so the username preview card and any
      // downstream code that reads `model.username` reflect the
      // prefilled value before the user types.
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
      _available = null; // Clear indicator while in flight
      // Once the user has touched the field, the "RESERVED FOR YOU"
      // eyebrow is no longer accurate — the new input might be a
      // different tag entirely. Hide it.
      _showingReservedBadge = false;
    });

    final tag = value.trim().toLowerCase();
    if (tag.isEmpty || tag.length < 3) return;
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(tag)) return;
    if (tag.startsWith('.') || tag.startsWith('_') || tag.endsWith('.') || tag.endsWith('_')) {
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final model = ZendScope.of(context);
        final isAvailable = await model.zendtagService.checkAvailability(tag);
        if (!mounted) return;
        setState(() {
          _available = isAvailable;
        });
      } catch (_) {
        // On error, show nothing (leave _available as null)
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final username = _controller.text.trim().isEmpty ? '' : _controller.text.trim().toLowerCase();

    return Scaffold(
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
                      _showingReservedBadge
                          ? 'Your @, as you reserved it.'
                          : 'Choose your @',
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_showingReservedBadge) ...[
                      const SizedBox(height: 6),
                      const Text(
                        "We held it for you. Keep it, or pick a different one.",
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          color: ZendColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_showingReservedBadge) ...[
                      const Text(
                        'RESERVED FOR YOU',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          letterSpacing: 1.8,
                          color: ZendColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '@',
                            style: const TextStyle(
                              fontFamily: 'DMMono',
                              color: ZendColors.textSecondary,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onChanged: (value) {
                              _scheduleCheck(value);
                              model.setUsername(value);
                            },
                            style: const TextStyle(fontFamily: 'DMMono', fontSize: 20, color: ZendColors.textPrimary),
                            decoration: const InputDecoration(
                              filled: false,
                              border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
                              hintText: 'yourname',
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
                                  style: TextStyle(
                                    color: _available! ? ZendColors.positive : ZendColors.destructive,
                                    fontSize: 24,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _PreviewCard(username: username),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Continue',
                      onPressed: () {
                        pushZendSlide(context, const KycScreen());
                      },
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
    final safeUsername = username.isEmpty ? 'yourname' : username;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZendColors.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ZendColors.bgPrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.alternate_email, color: ZendColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Zend Link',
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'zdfi.me/',
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 13, color: ZendColors.textSecondary),
              ),
              Text(
                safeUsername,
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 13, color: ZendColors.textPrimary),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: ZendColors.accentPop, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 18, color: ZendColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
