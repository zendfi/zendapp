import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'pool.dart';
import 'pool_detail_screen.dart';
import 'pool_info_card.dart';

/// Opens the Pool List Drawer as a modal bottom sheet.
Future<void> showPoolListDrawer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: PoolListDrawer(),
    ),
  );
}

/// A drawer listing all active pools as [PoolInfoCard] widgets.
///
/// When no active pools exist an empty-state message is shown instead.
/// Tapping a card dismisses the drawer and navigates to [PoolDetailScreen].
class PoolListDrawer extends StatelessWidget {
  const PoolListDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final activePools =
        model.pools.where((p) => p.status == PoolStatus.active).toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ZendSheetHandle(),
          const SizedBox(height: ZendSpacing.lg),
          const Text(
            'Pools',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),
          if (activePools.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No active pools yet',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: ZendColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: activePools.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ZendSpacing.sm),
                itemBuilder: (context, index) {
                  final pool = activePools[index];
                  return PoolInfoCard(
                    pool: pool,
                    onTap: () {
                      Navigator.of(context).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        pushZendSlide(
                          context,
                          PoolDetailScreen(pool: pool),
                          rootNavigator: true,
                        );
                      });
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
