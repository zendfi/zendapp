import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import 'loader_screen.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ZendScope.of(context),
      builder: (context, _) {
        final model = ZendScope.of(context);
        return Stack(
          children: [
            child,
            if (model.isLoading) ...[
              // Dismiss keyboard whenever the loader is shown
              Builder(builder: (ctx) {
                FocusScope.of(ctx).unfocus();
                return const SizedBox.shrink();
              }),
              LoaderScreen(
                message: model.loadingMessage,
                showLogo: true,
              ),
            ],
          ],
        );
      },
    );
  }
}
