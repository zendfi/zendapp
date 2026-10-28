import 'dart:js_interop';

/// `new ZXing.BrowserQRCodeReader().decodeFromImageUrl(url)` from the
/// self-hosted zxing-0.21.3.min.js (see web/index.html).
@JS('ZXing.BrowserQRCodeReader')
extension type _QrReader._(JSObject _) implements JSObject {
  external _QrReader();
  external JSPromise<_Result> decodeFromImageUrl(JSString url);
}

extension type _Result._(JSObject _) implements JSObject {
  external JSString getText();
}

Future<String?> decodeQrFromImageUrl(String url) async {
  try {
    final r = await _QrReader().decodeFromImageUrl(url.toJS).toDart;
    return r.getText().toDart;
  } catch (_) {
    return null; // no QR found, or decoder not loaded
  }
}
