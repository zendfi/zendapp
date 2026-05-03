import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class CustomisePageScreen extends StatefulWidget {
  const CustomisePageScreen({super.key});

  @override
  State<CustomisePageScreen> createState() => _CustomisePageScreenState();
}

class _CustomisePageScreenState extends State<CustomisePageScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _successMessage;

  final _bioController = TextEditingController();
  final _displayNameController = TextEditingController();
  String _themeColor = '#2D6A4F';
  String _backgroundColor = '#FAFAF7';
  String _accentColor = '#52B788';
  String _linkStyle = 'card';
  bool _showRecentActivity = false;

  static const _presetColors = [
    '#2D6A4F',
    '#1A1A2E',
    '#C94F2A',
    '#7B2D8B',
    '#1565C0',
    '#E65100',
    '#2E7D32',
    '#37474F',
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomisation();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomisation() async {
    setState(() => _loading = true);
    try {
      final model = ZendScope.of(context);
      final data =
          await model.walletService.apiClient.getMyPageCustomisation();
      setState(() {
        _themeColor = data['theme_color'] as String? ?? '#2D6A4F';
        _backgroundColor =
            data['background_color'] as String? ?? '#FAFAF7';
        _accentColor = data['accent_color'] as String? ?? '#52B788';
        _bioController.text = data['bio'] as String? ?? '';
        _displayNameController.text =
            data['display_name_override'] as String? ?? '';
        _linkStyle = data['link_style'] as String? ?? 'card';
        _showRecentActivity =
            data['show_recent_activity'] as bool? ?? false;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final model = ZendScope.of(context);
      await model.walletService.apiClient.updateMyPageCustomisation({
        'theme_color': _themeColor,
        'background_color': _backgroundColor,
        'accent_color': _accentColor,
        'bio': _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        'display_name_override':
            _displayNameController.text.trim().isEmpty
                ? null
                : _displayNameController.text.trim(),
        'link_style': _linkStyle,
        'show_recent_activity': _showRecentActivity,
      });
      setState(() {
        _saving = false;
        _successMessage = 'Saved!';
      });
      Timer(
        const Duration(seconds: 2),
        () => mounted ? setState(() => _successMessage = null) : null,
      );
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Failed to save. Please try again.';
      });
    }
  }

  Color _hexToColor(String hex) {
    try {
      return Color(
          int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return ZendColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final zendtag = model.currentZendtag ?? model.username;

    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back,
                        color: ZendColors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Customise page',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: ZendColors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: _successMessage != null
                        ? Center(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                color: ZendColors.positive,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: ZendColors.accent,
                                    ),
                                  )
                                : const Text(
                                    'Save',
                                    style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontWeight: FontWeight.w600,
                                      color: ZendColors.accent,
                                    ),
                                  ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(child: Center(child: ZendLoader()))
              else
                Expanded(
                  child: ZendScrollPage(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Live preview
                        _buildPreview(zendtag),
                        const SizedBox(height: 24),

                        // Display name
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ZendColors.bgSecondary,
                            borderRadius:
                                BorderRadius.circular(ZendRadii.xxl),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionLabel('Display name'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _displayNameController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Override your display name (optional)',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 16),
                              const _SectionLabel('Bio'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _bioController,
                                maxLines: 3,
                                maxLength: 160,
                                decoration: const InputDecoration(
                                  hintText: 'Tell people what you do...',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Layout style
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ZendColors.bgSecondary,
                            borderRadius:
                                BorderRadius.circular(ZendRadii.xxl),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionLabel('Layout style'),
                              const SizedBox(height: 12),
                              _StyleSelector(
                                selected: _linkStyle,
                                onChanged: (s) =>
                                    setState(() => _linkStyle = s),
                                themeColor: _hexToColor(_themeColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Colors
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ZendColors.bgSecondary,
                            borderRadius:
                                BorderRadius.circular(ZendRadii.xxl),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionLabel('Theme color'),
                              const SizedBox(height: 12),
                              _ColorPicker(
                                selected: _themeColor,
                                colors: _presetColors,
                                onChanged: (c) =>
                                    setState(() => _themeColor = c),
                              ),
                              const SizedBox(height: 16),
                              const _SectionLabel('Background color'),
                              const SizedBox(height: 12),
                              _ColorPicker(
                                selected: _backgroundColor,
                                colors: const [
                                  '#FAFAF7',
                                  '#FFFFFF',
                                  '#F0F4F8',
                                  '#1C2B1E',
                                  '#1A1A2E',
                                  '#0D0D0D',
                                ],
                                onChanged: (c) =>
                                    setState(() => _backgroundColor = c),
                              ),
                              const SizedBox(height: 16),
                              const _SectionLabel('Accent color'),
                              const SizedBox(height: 12),
                              _ColorPicker(
                                selected: _accentColor,
                                colors: _presetColors,
                                onChanged: (c) =>
                                    setState(() => _accentColor = c),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Show recent activity toggle
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: ZendColors.bgSecondary,
                            borderRadius:
                                BorderRadius.circular(ZendRadii.xxl),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Show recent activity',
                                      style: TextStyle(
                                        fontFamily: 'DMSans',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: ZendColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Display recent payment count on your page',
                                      style: TextStyle(
                                        fontFamily: 'DMSans',
                                        fontSize: 12,
                                        color: ZendColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _showRecentActivity,
                                onChanged: (v) => setState(
                                    () => _showRecentActivity = v),
                                activeThumbColor: ZendColors.accentBright,
                                activeTrackColor: ZendColors.accentBright
                                    .withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              color: ZendColors.destructive,
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Save changes',
                          onPressed: _saving ? () {} : _save,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(String zendtag) {
    final themeColor = _hexToColor(_themeColor);
    final bgColor = _hexToColor(_backgroundColor);
    final displayName = _displayNameController.text.trim().isNotEmpty
        ? _displayNameController.text.trim()
        : (ZendScope.of(context).currentDisplayName ?? zendtag);
    final bio = _bioController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Preview'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(ZendRadii.xxl),
            border: Border.all(color: ZendColors.border),
          ),
          padding: const EdgeInsets.all(20),
          child: switch (_linkStyle) {
            'minimal' => Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: themeColor,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'Z',
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'InstrumentSerif',
                          fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      Text('@$zendtag',
                          style: const TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 11,
                              color: ZendColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            'full' => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [themeColor, _hexToColor(_accentColor)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(ZendRadii.xl),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.3),
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : 'Z',
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'InstrumentSerif',
                            fontSize: 24),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(displayName,
                        style: const TextStyle(
                            fontFamily: 'InstrumentSerif',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    Text('zdfi.me/@$zendtag',
                        style: const TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 11,
                            color: Colors.white70)),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(bio,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              color: Colors.white70)),
                    ],
                  ],
                ),
              ),
            _ => Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: themeColor,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'Z',
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'InstrumentSerif',
                          fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(displayName,
                      style: const TextStyle(
                          fontFamily: 'InstrumentSerif',
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  Text('zdfi.me/@$zendtag',
                      style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          color: ZendColors.textSecondary)),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            color: ZendColors.textSecondary)),
                  ],
                ],
              ),
          },
        ),
      ],
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
        letterSpacing: 1.1,
        color: ZendColors.textSecondary,
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.selected,
    required this.colors,
    required this.onChanged,
  });

  final String selected;
  final List<String> colors;
  final ValueChanged<String> onChanged;

  Color _hex(String hex) {
    try {
      return Color(
          int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: colors.map((color) {
        final isSelected = color == selected;
        return GestureDetector(
          onTap: () => onChanged(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hex(color),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? ZendColors.textPrimary
                    : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _hex(color).withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 16,
                    color: _hex(color).computeLuminance() > 0.4
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _StyleSelector extends StatelessWidget {
  const _StyleSelector({
    required this.selected,
    required this.onChanged,
    required this.themeColor,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    const styles = [
      ('minimal', 'Minimal', 'Compact header'),
      ('card', 'Card', 'Centered avatar'),
      ('full', 'Full', 'Gradient banner'),
    ];

    return Row(
      children: styles.map((s) {
        final (value, label, desc) = s;
        final isSelected = selected == value;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? themeColor.withValues(alpha: 0.1)
                    : ZendColors.bgPrimary,
                borderRadius: BorderRadius.circular(ZendRadii.lg),
                border: Border.all(
                  color: isSelected ? themeColor : ZendColors.border,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? themeColor
                          : ZendColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 10,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
