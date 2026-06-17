import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A singleton that collects timestamped Drop debug events and broadcasts them
/// to any listening UI panels.
///
/// Usage:
///   DropDebugLog.i.add('BLE', 'Scan started');
///   DropDebugLog.i.add('GATT', 'Connected to AA:BB:CC:DD', level: DropLogLevel.ok);
///   DropDebugLog.i.add('ADV', 'Start failed: data too large', level: DropLogLevel.error);
class DropDebugLog {
  DropDebugLog._();
  static final DropDebugLog i = DropDebugLog._();

  static const int _maxEntries = 120;

  final List<DropLogEntry> _entries = [];
  final _controller = StreamController<List<DropLogEntry>>.broadcast();

  Stream<List<DropLogEntry>> get stream => _controller.stream;
  List<DropLogEntry> get entries => List.unmodifiable(_entries);

  void add(String tag, String message, {DropLogLevel level = DropLogLevel.info}) {
    final entry = DropLogEntry(
      time: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    _controller.add(List.unmodifiable(_entries));

    // Also print to console so flutter logs catch it
    final prefix = switch (level) {
      DropLogLevel.ok    => '✅',
      DropLogLevel.warn  => '⚠️',
      DropLogLevel.error => '❌',
      DropLogLevel.info  => '🔵',
    };
    debugPrint('DROP[$tag] $prefix $message');
  }

  void clear() {
    _entries.clear();
    _controller.add([]);
  }

  void dispose() {
    _controller.close();
  }

  /// Reads the persistent crash log written by MainActivity on Android.
  /// Returns null on non-Android or if the channel is unavailable.
  static Future<String?> readAndClearNativeCrashLog() async {
    if (!Platform.isAndroid) return null;
    try {
      const ch = MethodChannel('com.zendfi.app/drop_diagnostics');
      final log = await ch.invokeMethod<String>('readCrashLog');
      if (log != null && log.isNotEmpty) {
        await ch.invokeMethod('clearCrashLog');
      }
      return log;
    } catch (_) {
      return null;
    }
  }

  /// Returns all entries as a plain-text string, suitable for clipboard copy.
  String toClipboardText() {
    return _entries
        .map((e) {
          final hh = e.time.hour.toString().padLeft(2, '0');
          final mm = e.time.minute.toString().padLeft(2, '0');
          final ss = e.time.second.toString().padLeft(2, '0');
          final ms = e.time.millisecond.toString().padLeft(3, '0');
          return '[$hh:$mm:$ss.$ms][${e.tag}] ${e.message}';
        })
        .join('\n');
  }
}

enum DropLogLevel { info, ok, warn, error }

class DropLogEntry {
  const DropLogEntry({
    required this.time,
    required this.tag,
    required this.message,
    required this.level,
  });

  final DateTime time;
  final String tag;
  final String message;
  final DropLogLevel level;
}

// ── In-app overlay panel ──────────────────────────────────────────────────────

/// A semi-transparent scrollable overlay that shows the Drop debug log in real
/// time. Wrap the Drop sheet stack with this:
///
/// ```dart
/// Stack(children: [
///   DropSheet(amount: amount),
///   const DropDebugPanel(),
/// ])
/// ```
///
/// Or show it independently via [showDropDebugOverlay].
class DropDebugPanel extends StatefulWidget {
  const DropDebugPanel({super.key});

  @override
  State<DropDebugPanel> createState() => _DropDebugPanelState();
}

class _DropDebugPanelState extends State<DropDebugPanel> {
  final _scrollController = ScrollController();
  StreamSubscription<List<DropLogEntry>>? _sub;
  List<DropLogEntry> _entries = List.unmodifiable(DropDebugLog.i.entries);
  bool _pinned = true;
  Timer? _rebuildTimer;
  String? _nativeCrashLog;

  @override
  void initState() {
    super.initState();
    _sub = DropDebugLog.i.stream.listen((entries) {
      _rebuildTimer?.cancel();
      _rebuildTimer = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() => _entries = entries);
        if (_pinned) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
              );
            }
          });
        }
      });
    });
    // Load native crash log on open
    DropDebugLog.readAndClearNativeCrashLog().then((log) {
      if (log != null && log.isNotEmpty && mounted) {
        setState(() => _nativeCrashLog = log);
        // Also inject into in-memory log so it shows inline
        for (final line in log.split('\n')) {
          if (line.trim().isNotEmpty) {
            DropDebugLog.i.add('NATIVE', line.trim(), level: DropLogLevel.warn);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _rebuildTimer?.cancel();
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _levelColor(DropLogLevel level) {
    return switch (level) {
      DropLogLevel.ok    => const Color(0xFF52B788),
      DropLogLevel.warn  => const Color(0xFFFFC107),
      DropLogLevel.error => const Color(0xFFFF5252),
      DropLogLevel.info  => const Color(0xFF90CAF9),
    };
  }

  String _levelIcon(DropLogLevel level) {
    return switch (level) {
      DropLogLevel.ok    => '✓',
      DropLogLevel.warn  => '!',
      DropLogLevel.error => '✗',
      DropLogLevel.info  => '·',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.38,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xE6050E08), // ~90% opaque dark green
            border: Border(
              top: BorderSide(color: const Color(0xFF52B788).withValues(alpha: 0.4), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header bar
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Text(
                      'DROP DEBUG',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 10,
                        color: Color(0xFF52B788),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_entries.length} events',
                      style: const TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 10,
                        color: Color(0x80F0F0F0),
                      ),
                    ),
                    const Spacer(),
                    // Pin/unpin auto-scroll
                    GestureDetector(
                      onTap: () => setState(() => _pinned = !_pinned),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          _pinned ? '⬇ LIVE' : '⏸ PAUSED',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 9,
                            color: _pinned
                                ? const Color(0xFF52B788)
                                : const Color(0x80F0F0F0),
                          ),
                        ),
                      ),
                    ),
                    // Copy to clipboard
                    GestureDetector(
                      onTap: () async {
                        final combined = [
                          if (_nativeCrashLog != null) '=== NATIVE CRASH LOG ===\n$_nativeCrashLog\n=== DART LOG ===',
                          DropDebugLog.i.toClipboardText(),
                        ].join('\n');
                        await Clipboard.setData(ClipboardData(text: combined));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Drop log copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          'COPY',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 9,
                            color: Color(0x80F0F0F0),
                          ),
                        ),
                      ),
                    ),
                    // Clear
                    GestureDetector(
                      onTap: () {
                        DropDebugLog.i.clear();
                        setState(() => _entries = []);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          'CLR',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 9,
                            color: Color(0x80F0F0F0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x33F0F0F0)),
              // Log entries
              Expanded(
                child: _entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Waiting for events…',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 11,
                            color: Color(0x44F0F0F0),
                          ),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n is ScrollUpdateNotification) {
                            final atBottom = _scrollController.position.pixels >=
                                _scrollController.position.maxScrollExtent - 16;
                            if (_pinned != atBottom) {
                              setState(() => _pinned = atBottom);
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final e = _entries[index];
                            final hh = e.time.hour.toString().padLeft(2, '0');
                            final mm = e.time.minute.toString().padLeft(2, '0');
                            final ss = e.time.second.toString().padLeft(2, '0');
                            final ms = (e.time.millisecond ~/ 10).toString().padLeft(2, '0');
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 1,
                              ),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontFamily: 'DMMono',
                                    fontSize: 10.5,
                                    height: 1.4,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '$hh:$mm:$ss.$ms ',
                                      style: const TextStyle(
                                        color: Color(0x66F0F0F0),
                                      ),
                                    ),
                                    TextSpan(
                                      text: '[${e.tag}] ',
                                      style: const TextStyle(
                                        color: Color(0xAAF0F0F0),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '${_levelIcon(e.level)} ',
                                      style: TextStyle(
                                        color: _levelColor(e.level),
                                      ),
                                    ),
                                    TextSpan(
                                      text: e.message,
                                      style: TextStyle(
                                        color: _levelColor(e.level)
                                            .withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a persistent floating debug panel above the current page.
/// Call this once from the Drop sheet's [initState] during debug builds.
void showDropDebugOverlay(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => const Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 260,
      child: DropDebugPanel(),
    ),
  );
  overlay.insert(entry);
}
