import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../send_note/send_note_screen.dart';

class RecipientSelectionScreen extends StatelessWidget {
  const RecipientSelectionScreen({super.key, required this.amount});

  final num amount;

  void _openSendNote(BuildContext context, SendNoteScreen screen) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushZendSlide(context, screen, rootNavigator: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep.withValues(alpha: 0.6),
      body: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: const BoxDecoration(
              color: ZendColors.bgPrimary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ZendScrollPage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ZendSheetHandle(),
                    const SizedBox(height: 20),
                    Text(
                      'Pay \$${amount.toStringAsFixed(0)} to',
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _SearchField(hintText: 'Name, @username, phone...'),
                    const SizedBox(height: 18),
                    const _SectionLabel('ZendApp users'),
                    const SizedBox(height: 12),
                    _ContactTile(
                      name: 'Amara Nwosu',
                      handle: '@amara_n',
                      avatarLabel: 'A',
                      onTap: () {
                        _openSendNote(
                          context,
                          SendNoteScreen(
                            recipientName: 'Amara Nwosu',
                            handle: '@amara_n',
                            amount: amount,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _ContactTile(
                      name: 'Tunde Bakare',
                      handle: '@tunde_b',
                      avatarLabel: 'T',
                      onTap: () {
                        _openSendNote(
                          context,
                          SendNoteScreen(
                            recipientName: 'Tunde Bakare',
                            handle: '@tunde_b',
                            amount: amount,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _ContactTile(
                      name: 'David Ojo',
                      handle: '@david.ojo',
                      avatarLabel: 'D',
                      onTap: () {
                        _openSendNote(
                          context,
                          SendNoteScreen(
                            recipientName: 'David Ojo',
                            handle: '@david.ojo',
                            amount: amount,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const _SectionLabel('External'),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        _openSendNote(
                          context,
                          SendNoteScreen(
                            recipientName: 'Bank account',
                            handle: 'Nigeria, UK, USA, Europe',
                            amount: amount,
                            external: true,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ZendColors.bgPrimary,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: ZendColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: ZendColors.bgSecondary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.account_balance_outlined),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Send to bank account', style: TextStyle(fontSize: 15)),
                                  SizedBox(height: 2),
                                  Text(
                                    'Nigeria, UK, USA, Europe',
                                    style: TextStyle(fontSize: 12, color: ZendColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: ZendColors.textSecondary,
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hintText});

  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20, color: ZendColors.textSecondary),
        filled: true,
        fillColor: ZendColors.bgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.name, required this.handle, required this.avatarLabel, required this.onTap});

  final String name;
  final String handle;
  final String avatarLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: ZendColors.bgSecondary,
              child: Text(avatarLabel, style: const TextStyle(color: ZendColors.textPrimary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    handle,
                    style: const TextStyle(fontFamily: 'DMMono', fontSize: 13, color: ZendColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: ZendColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
