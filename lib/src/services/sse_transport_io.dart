import 'package:dio/dio.dart';

import 'sse_transport_base.dart';

Future<SseConnection> openSseConnection(
  Uri url,
  Map<String, String> headers,
) async {
  final cancelToken = CancelToken();
  final dio = Dio(
    BaseOptions(
      headers: headers,
      responseType: ResponseType.stream,
      // No receive timeout: the connection is meant to stay open.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: null,
      // Let the caller read the status (401 stops reconnecting).
      validateStatus: (_) => true,
    ),
  );
  final response = await dio.getUri<ResponseBody>(
    url,
    cancelToken: cancelToken,
  );
  return SseConnection(
    statusCode: response.statusCode ?? 0,
    bytes: response.data?.stream ?? const Stream<List<int>>.empty(),
    close: () => cancelToken.cancel('SSE stopped'),
  );
}
