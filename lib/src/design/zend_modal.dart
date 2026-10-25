import 'package:flutter/material.dart';

import 'zend_tokens.dart';
import 'zend_web_frame.dart';

/// Drop-in replacement for [showModalBottomSheet] used across the app.
///
/// On phones (and narrow browser windows) it *is* showModalBottomSheet.
/// On a wide web window a sheet sliding up from the bottom edge of a monitor
/// reads as a phone UI, so the same content opens as a centred dialog
/// instead. The sheet's widget is reused untouched: it is given a
/// phone-sized box and a matching [MediaQuery], so sheets that size
/// themselves from `MediaQuery.size` or a `FractionallySizedBox` behave
/// exactly as they do on a phone.
Future<T?> showZendModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
}) {
  if (!ZendWebLayout.isWide(context)) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      shape: shape,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
    );
  }

  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: isDismissible,
    barrierColor: const Color(0x8C000000),
    builder: (dialogContext) => _SheetAsDialog(
      backgroundColor: backgroundColor,
      child: builder(dialogContext),
    ),
  );
}

class _SheetAsDialog extends StatelessWidget {
  const _SheetAsDialog({required this.child, this.backgroundColor});

  final Widget child;
  final Color? backgroundColor;

  static const double _width = 480;
  static const double _maxHeight = 780;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final media = MediaQuery.of(context);
    final height = (media.size.height * 0.88).clamp(320.0, _maxHeight);
    // Sheets that paint their own surface pass a transparent background;
    // give them the app surface behind so rounded corners don't show the
    // barrier through.
    final bg =
        (backgroundColor == null || backgroundColor == Colors.transparent)
        ? zt.bgPrimary
        : backgroundColor!;

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: zt.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _width, maxHeight: height),
        child: MediaQuery(
          data: media.copyWith(
            size: Size(_width, height),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );
  }
}
