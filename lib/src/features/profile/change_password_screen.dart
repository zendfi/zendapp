import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: 'Change password'),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: zt.bgSecondary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _currentController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Current password'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'New password'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirm password'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(label: 'Update password', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back, color: zt.textPrimary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}
