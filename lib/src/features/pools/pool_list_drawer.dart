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

/// A drawer listing all pools grouped by status.
///
/// Shows a loading indicator while pools are being fetched, an error state
/// with a retry button on failure, and a sectioned list (Active / Completed /
/// Expired / Cancelled) when data is available.
class PoolListDrawer extends StatelessWidget {
  const PoolListDrawer({super.key});

  void _navigateToPool(BuildContext context, Pool pool) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushZendSlide(
        context,
        PoolDetailScreen(pool: pool),
        rootNavigator: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);

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
          Expanded(child: _buildBody(context, model)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ZendAppModel model) {
    // Loading state
    if (model.poolsLoading && model.pools.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(ZendColors.accentBright),
        ),
      );
    }

    // Error state
    if (model.lastPoolsError != null && model.pools.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Failed to load pools',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: ZendColors.textSecondary,
              ),
            ),
            const SizedBox(height: ZendSpacing.sm),
            TextButton(
              onPressed: () => model.fetchPools(),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontWeight: FontWeight.w600,
                  color: ZendColors.accentBright,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Partition pools by status
    final active =
        model.pools.where((p) => p.status == PoolStatus.active).toList();
    final completed =
        model.pools.where((p) => p.status == PoolStatus.completed).toList();
    final expired =
        model.pools.where((p) => p.status == PoolStatus.expired).toList();
    final cancelled =
        model.pools.where((p) => p.status == PoolStatus.cancelled).toList();

    if (model.pools.isEmpty) {
      return const Center(
        child: Text(
          'No pools yet',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            color: ZendColors.textSecondary,
          ),
        ),
      );
    }

    // Build a flat list of section headers + cards
    final items = <Widget>[];

    void addSection(String title, List<Pool> pools) {
      if (pools.isEmpty) return;
      items.add(_SectionHeader(title: title));
      for (final pool in pools) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(bottom: ZendSpacing.sm),
            child: PoolInfoCard(
              pool: pool,
              onTap: () => _navigateToPool(context, pool),
            ),
          ),
        );
      }
    }

    addSection('Active', active);
    addSection('Completed', completed);
    addSection('Expired', expired);
    addSection('Cancelled', cancelled);

    return ListView(children: items);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZendSpacing.xs, top: ZendSpacing.xs),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'DMSans',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ZendColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Status badge for non-active pools shown on [PoolInfoCard].
class PoolStatusBadge extends StatelessWidget {
  const PoolStatusBadge({super.key, required this.status});
  final PoolStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == PoolStatus.active) return const SizedBox.shrink();

    final (label, color) = switch (status) {
      PoolStatus.completed => ('Completed', ZendColors.accent),
      PoolStatus.expired => ('Expired', ZendColors.destructive),
      PoolStatus.cancelled => ('Cancelled', ZendColors.textSecondary),
      _ => ('', ZendColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZendRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
