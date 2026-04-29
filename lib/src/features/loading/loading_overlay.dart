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
            if (model.isLoading)
              LoaderScreen(
                message: model.loadingMessage,
                showLogo: true,
              ),
          ],
        );
      },
    );
  }
}
