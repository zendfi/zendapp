import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import 'pool.dart';

Future<void> showManageSheet(
  BuildContext context, {
  required Pool pool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ManageSheet(pool: pool),
  );
}

class ManageSheet extends StatefulWidget {
  const ManageSheet({super.key, required this.pool});
  final Pool pool;

  @override
  State<ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<ManageSheet> {
  bool _loading = false;
  String? _error;
  bool _confirmed = false;

  Future<void> _cancelPool() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final model = ZendScope.of(context);
      await model.walletService.apiClient.cancelPool(widget.pool.id);

      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ZendSheetHandle(),
          const SizedBox(height: ZendSpacing.lg),

          const Text(
            'Manage pool',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ZendSpacing.xl),

          if (!_confirmed) ...[
            GestureDetector(
              onTap: () => setState(() => _confirmed = true),
              child: Container(
                padding: const EdgeInsets.all(ZendSpacing.md),
                decoration: BoxDecoration(
                  color: ZendColors.destructive.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(ZendRadii.md),
                  border: Border.all(
                    color: ZendColors.destructive.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: ZendColors.destructive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(ZendRadii.sm),
                      ),
                      child: const Icon(
                        Icons.cancel_outlined,
                        color: ZendColors.destructive,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: ZendSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cancel pool',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ZendColors.destructive,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Closes the pool and Mission Room',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 12,
                              color: ZendTheme.of(context).textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: ZendTheme.of(context).textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(ZendSpacing.md),
              decoration: BoxDecoration(
                color: ZendTheme.of(context).bgCard,
                borderRadius: BorderRadius.circular(ZendRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cancel this pool?',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ZendTheme.of(context).textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.xs),
                  Text(
                    'This will permanently close "${widget.pool.name}" and the Mission Room. '
                    'Contributors are not automatically refunded — contributions were sent '
                    'directly to your wallet.',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14,
                      color: ZendTheme.of(context).textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ZendSpacing.lg),

            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.destructive,
                ),
              ),
              const SizedBox(height: ZendSpacing.sm),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _confirmed = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZendTheme.of(context).textSecondary,
                      side: BorderSide(color: ZendTheme.of(context).border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.lg),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Go back',
                      style: TextStyle(fontFamily: 'DMSans'),
                    ),
                  ),
                ),
                const SizedBox(width: ZendSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : _cancelPool,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZendColors.destructive,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.lg),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          )
                        : const Text(
                            'Cancel pool',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
