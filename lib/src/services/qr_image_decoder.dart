import 'qr_image_decoder_web.dart'
    if (dart.library.io) 'qr_image_decoder_io.dart'
    as impl;

/// Decodes a QR code from an image URL (web: the blob URL image_picker
/// returns). Returns null if none is found. Mobile scans live instead.
Future<String?> decodeQrFromImageUrl(String url) =>
    impl.decodeQrFromImageUrl(url);
