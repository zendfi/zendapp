import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ziro_vision.dart';

/// Live camera preview backed by a Flutter [Texture] (Android SurfaceProducer,
/// iOS FlutterTexture). Fills its box, cropping like `BoxFit.cover`, and shows
/// the selfie (mirrored) view.
///
/// Opens the camera on mount and releases the texture on dispose. A running
/// capture keeps the camera on after the preview closes.
class ZiroPreview extends StatefulWidget {
  const ZiroPreview({
    super.key,
    required this.vision,
    this.placeholder,
    this.onError,
  });

  final ZiroVision vision;

  /// Shown until the first preview description arrives, and on error.
  final Widget? placeholder;

  /// Receives `camera_denied` / `camera_failed` errors from opening.
  final ValueChanged<PlatformException>? onError;

  @override
  State<ZiroPreview> createState() => _ZiroPreviewState();
}

class _ZiroPreviewState extends State<ZiroPreview> {
  PreviewInfo? _info;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final info = await widget.vision.openPreview();
      if (_disposed) {
        await widget.vision.closePreview();
        return;
      }
      setState(() => _info = info);
    } on PlatformException catch (e) {
      if (!_disposed) widget.onError?.call(e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_info != null) {
      widget.vision.closePreview();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return widget.placeholder ?? const SizedBox.expand();
    Widget tex = Texture(textureId: info.textureId);
    tex = SizedBox(
      width: info.width.toDouble(),
      height: info.height.toDouble(),
      child: tex,
    );
    if (info.quarterTurns % 4 != 0) {
      tex = RotatedBox(quarterTurns: info.quarterTurns, child: tex);
    }
    if (info.mirror) {
      tex = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: tex,
      );
    }
    return ClipRect(
      child: LayoutBuilder(builder: (context, box) {
        final w = info.quarterTurns.isOdd ? info.height : info.width;
        final h = info.quarterTurns.isOdd ? info.width : info.height;
        final scale = box.hasBoundedWidth && box.hasBoundedHeight
            ? math.max(box.maxWidth / w, box.maxHeight / h)
            : 1.0;
        return OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: w * scale,
            height: h * scale,
            child: FittedBox(fit: BoxFit.fill, child: tex),
          ),
        );
      }),
    );
  }
}
