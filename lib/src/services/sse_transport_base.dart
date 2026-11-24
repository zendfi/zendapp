/// An open live-updates connection: the HTTP status and the raw body bytes as
/// they arrive. [close] ends it; the [bytes] stream then errors or completes.
class SseConnection {
  SseConnection({
    required this.statusCode,
    required this.bytes,
    required void Function() close,
  }) : _close = close;

  final int statusCode;
  final Stream<List<int>> bytes;
  final void Function() _close;

  void close() => _close();
}
