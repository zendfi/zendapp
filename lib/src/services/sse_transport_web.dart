import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sse_transport_base.dart';

/// Streams the response body chunk by chunk with `fetch`, so each event
/// reaches the app as soon as the server writes it.
Future<SseConnection> openSseConnection(
  Uri url,
  Map<String, String> headers,
) async {
  final abort = web.AbortController();
  final requestHeaders = web.Headers();
  // JS interop members can't be torn off, so wrap them in closures.
  headers.forEach((k, v) => requestHeaders.append(k, v));

  final response = await web.window
      .fetch(
        url.toString().toJS,
        web.RequestInit(
          method: 'GET',
          headers: requestHeaders,
          cache: 'no-store',
          signal: abort.signal,
        ),
      )
      .toDart
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          abort.abort();
          throw TimeoutException('SSE connect timed out');
        },
      );

  final body = response.body;
  if (body == null) {
    return SseConnection(
      statusCode: response.status,
      bytes: const Stream<List<int>>.empty(),
      close: () => abort.abort(),
    );
  }

  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  late final StreamController<List<int>> controller;
  var cancelled = false;

  Future<void> pump() async {
    try {
      while (!cancelled) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        final value = chunk.value;
        if (value != null && value.isA<JSUint8Array>()) {
          controller.add((value as JSUint8Array).toDart);
        }
      }
      if (!controller.isClosed) await controller.close();
    } catch (e, st) {
      // An abort from close() lands here too; the caller treats it as the end.
      if (!controller.isClosed) {
        controller.addError(e, st);
        await controller.close();
      }
    }
  }

  controller = StreamController<List<int>>(
    onListen: () => unawaited(pump()),
    onCancel: () {
      cancelled = true;
      abort.abort();
    },
  );

  return SseConnection(
    statusCode: response.status,
    bytes: controller.stream,
    close: () {
      cancelled = true;
      abort.abort();
    },
  );
}
