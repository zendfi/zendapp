/// Opens the byte stream behind [SseService].
///
/// Mobile uses Dio. Web can't: Dio's web adapter is XMLHttpRequest with
/// `responseType = 'arraybuffer'`, which hands over nothing until the response
/// ends (a live stream never ends), and it sets `xhr.timeout` to
/// connectTimeout + receiveTimeout, which cut every connection at 10s. The web
/// build reads the body with `fetch` and a `ReadableStream` reader instead.
library;

export 'sse_transport_base.dart';
export 'sse_transport_io.dart'
    if (dart.library.js_interop) 'sse_transport_web.dart';
