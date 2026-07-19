import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'package:solar_icons/solar_icons.dart';

class ContactSupportScreen extends StatelessWidget {
  const ContactSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(title: 'Contact support'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Response time banner ───────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: zt.accentBright.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(ZendRadii.xl),
                      ),
                      child: Row(
                        children: [
                          Icon(SolarIconsBold.lightning,
                              size: 16, color: zt.accentBright),
                          const SizedBox(width: 8),
                          Text(
                            'We respond in under 2 hours',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: zt.accentBright,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Contact options ────────────────────────────────
                    _SectionLabel('Get in touch'),
                    const SizedBox(height: 8),
                    _TileGroup(tiles: [
                      _ContactTile(
                        icon: SolarIconsBold.mailbox,
                        label: 'Email support',
                        subtitle: 'support@zendfi.com',
                        onTap: () async {
                          final uri =
                              Uri.parse('mailto:support@zendfi.com');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            await Clipboard.setData(const ClipboardData(
                                text: 'support@zendfi.com'));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Email copied to clipboard')),
                              );
                            }
                          }
                        },
                      ),
                      _ContactTile(
                        icon: SolarIconsBold.chatDots,
                        label: 'Live chat',
                        subtitle: 'Start a conversation',
                        onTap: () {},
                      ),
                      _ContactTile(
                        icon: SolarIconsBold.clipboard,
                        label: 'Help centre',
                        subtitle: 'Browse guides and FAQs',
                        onTap: () async {
                          final uri = Uri.parse('https://help.zendfi.com');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ]),

                    const SizedBox(height: 32),
                    PrimaryButton(
                      label: 'Start live chat',
                      onPressed: () {},
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: zt.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: zt.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 12,
                        color: zt.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(SolarIconsBold.altArrowRight,
                  size: 16, color: zt.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────

class _TileGroup extends StatelessWidget {
  const _TileGroup({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: ColoredBox(
        color: zt.bgSecondary,
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1)
                Divider(
                    height: 1,
                    thickness: 1,
                    color: zt.border,
                    indent: 48),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}

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
            icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
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
