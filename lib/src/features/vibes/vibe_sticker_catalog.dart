import '../../core/zend_state.dart';

/// A single Vibe sticker definition from the server catalog.
class VibeSticker {
  const VibeSticker({
    required this.id,
    required this.emoji,
    required this.label,
  });

  final String id;
  final String emoji;
  final String label;

  factory VibeSticker.fromJson(Map<String, dynamic> json) => VibeSticker(
        id: json['id'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '✨',
        label: json['label'] as String? ?? '',
      );
}

/// Singleton catalog — fetches stickers once per session then caches.
class VibeStickerCatalog {
  VibeStickerCatalog._();

  static final VibeStickerCatalog instance = VibeStickerCatalog._();

  List<VibeSticker>? _cache;

  // Fallback stickers shown while the network loads or on error.
  static const _fallback = [
    VibeSticker(id: 'fire', emoji: '🔥', label: 'Fire'),
    VibeSticker(id: 'heart', emoji: '❤️', label: 'Love'),
    VibeSticker(id: 'money', emoji: '💸', label: 'Money'),
    VibeSticker(id: 'clap', emoji: '👏', label: 'Respect'),
    VibeSticker(id: 'star', emoji: '⭐', label: 'Star'),
    VibeSticker(id: 'rocket', emoji: '🚀', label: 'Launch'),
    VibeSticker(id: 'crown', emoji: '👑', label: 'Crown'),
    VibeSticker(id: 'gift', emoji: '🎁', label: 'Gift'),
    VibeSticker(id: 'party', emoji: '🎉', label: 'Party'),
    VibeSticker(id: 'highfive', emoji: '🙏', label: 'Thanks'),
    VibeSticker(id: 'laugh', emoji: '😂', label: 'LOL'),
    VibeSticker(id: 'wave', emoji: '👋', label: 'Hey'),
  ];

  Future<List<VibeSticker>> getStickers(ZendAppModel model) async {
    if (_cache != null) return _cache!;
    try {
      final raw = await model.walletService.apiClient.getVibeStickers();
      _cache = raw
          .cast<Map<String, dynamic>>()
          .map(VibeSticker.fromJson)
          .toList();
      if (_cache!.isEmpty) _cache = List.of(_fallback);
      return _cache!;
    } catch (_) {
      return List.of(_fallback);
    }
  }

  void invalidate() => _cache = null;
}
