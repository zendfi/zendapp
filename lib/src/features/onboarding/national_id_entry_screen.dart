import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/cloud_backup_service.dart';
import '../../services/recovery_service.dart';

/// Collects a government ID number and creates the recovery packet.
///
/// Called from [RecoverySetupScreen] during onboarding or from settings.
class NationalIdEntryScreen extends StatefulWidget {
  const NationalIdEntryScreen({super.key, this.onComplete});

  /// Called on successful setup. If null, the navigator is popped.
  final VoidCallback? onComplete;

  @override
  State<NationalIdEntryScreen> createState() => _NationalIdEntryScreenState();
}

class _NationalIdEntryScreenState extends State<NationalIdEntryScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  // ── Country options ───────────────────────────────────────────────────────

  // Each entry: { 'code': 'NG', 'label': 'Nigeria', 'name': 'NIN', 'digits': 11 }
  static const _countries = [
    {'code': 'NG', 'label': 'Nigeria', 'name': 'NIN', 'digits': 11},
    {'code': 'GH', 'label': 'Ghana', 'name': 'Ghana Card', 'digits': 15},
    {'code': 'KE', 'label': 'Kenya', 'name': 'National ID', 'digits': 8},
    {'code': 'ZA', 'label': 'South Africa', 'name': 'ID Number', 'digits': 13},
    {'code': 'IN', 'label': 'India', 'name': 'Aadhaar', 'digits': 12},
    {'code': 'US', 'label': 'United States', 'name': 'SSN (last 4)', 'digits': 4},
    {'code': 'GB', 'label': 'United Kingdom', 'name': 'NI Number', 'digits': 9},
    {'code': 'OTHER', 'label': 'Other', 'name': 'Government ID', 'digits': 0},
  ];

  Map<String, dynamic> _selectedCountry = _countries[0];

  bool get _hasExpectedDigits {
    final digits = _selectedCountry['digits'] as int;
    if (digits == 0) return _controller.text.length >= 6; // Any ID ≥ 6 chars
    return _controller.text.replaceAll(RegExp(r'\s'), '').length == digits;
  }

  String get _hintText {
    final name = _selectedCountry['name'] as String;
    final digits = _selectedCountry['digits'] as int;
    if (digits == 0) return name;
    return '$name ($digits digits)';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawId = _controller.text.trim().replaceAll(RegExp(r'\s'), '');
    if (rawId.isEmpty) {
      setState(() => _error = 'Please enter your ID number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final model = ZendScope.of(context);
      await model.recoveryService.createRecoveryBackup(rawId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovery backup saved to your cloud storage.'),
          backgroundColor: ZendColors.positive,
        ),
      );

      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        Navigator.of(context).pop();
      }
    } on RecoverySetupRequiresUnlockException {
      setState(() => _error = 'App must be unlocked to set up recovery. Please restart and try again.');
    } on CloudBackupException catch (e) {
      setState(() => _error = 'Cloud storage error: ${e.message}. Please try again.');
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: zt.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Enter your government ID',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This number is combined with your wallet salt to create a recovery key — it never leaves your device.',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  height: 1.5,
                  color: zt.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Country selector — plain DropdownButton avoids the deprecated
              // FormField.value lint that fires on DropdownButtonFormField.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: zt.bgSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: zt.border),
                ),
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedCountry,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: zt.bgSecondary,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: zt.textPrimary,
                  ),
                  items: _countries
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c['label'] as String),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCountry = value;
                        _controller.clear();
                        _error = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ID input
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-A-Za-z]')),
                ],
                onChanged: (_) => setState(() => _error = null),
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 18,
                  letterSpacing: 2,
                  color: zt.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: _hintText,
                  hintStyle: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: zt.textSecondary,
                    letterSpacing: 0,
                  ),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: zt.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: zt.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: zt.accentBright, width: 1.5),
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Digit count hint
              if (_selectedCountry['digits'] as int > 0)
                Text(
                  '${_controller.text.replaceAll(RegExp(r'\s'), '').length} / ${_selectedCountry['digits']} digits',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: _hasExpectedDigits ? zt.accentBright : zt.textSecondary,
                  ),
                ),

              const SizedBox(height: 8),
              // Privacy note
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: zt.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your ID number is never sent to Zend\'s servers or stored in the cloud.',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 12,
                        color: zt.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                PrimaryButton(
                  label: 'Save recovery backup',
                  onPressed: _hasExpectedDigits ? _submit : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
