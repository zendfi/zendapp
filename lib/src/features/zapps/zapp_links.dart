import '../deeplink/deep_link_handler.dart';

/// Links to a ZApp (`app.usezend.app/apps/<slug>?…`) or one of its interactions
/// (`app.usezend.app/i/int_…`) inside a chat message. They open inside Zend, like
/// tapping the app's card. Every other link stays plain text.
///
/// Slugs follow the registry's rule (2-31 of a-z, 0-9, '-'). The scheme is optional,
/// so "app.usezend.app/apps/kobolt" works as typed.
final _zappLink = RegExp(
  r'(?:https?://)?app\.usezend\.app/(?:apps/[a-z0-9-]{2,31}|i/int_[A-Za-z0-9]+)/?(?:\?[^\s]*)?',
);

/// Punctuation a sentence puts after a link, never part of it.
final _trailing = RegExp(r'''[.,!?;:)\]'"]+$''');

/// A run of message text, and the ZApp it opens when it's a link.
class MessagePiece {
  const MessagePiece(this.text, [this.link]);
  final String text;
  final DeepLinkPayload? link;
}

/// The ZApp a single link opens, or null when it isn't a ZApp link. Launch params
/// are filtered exactly as for links opened from outside Zend ([zappLinkParams]).
DeepLinkPayload? parseZAppLink(String raw) {
  final m = _zappLink.matchAsPrefix(raw);
  if (m == null || m.end != raw.length) return null;
  final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
  if (uri == null || uri.pathSegments.length < 2) return null;
  final id = uri.pathSegments[1];
  if (uri.pathSegments[0] == 'i') {
    return DeepLinkPayload(zendtag: '', interactionId: id);
  }
  final params = zappLinkParams(uri.queryParameters);
  return DeepLinkPayload(
    zendtag: '',
    zappSlug: id,
    zappQuery: params.isEmpty ? null : params,
  );
}

/// Splits message text into plain runs and ZApp links. Text without a ZApp link
/// comes back as one plain piece.
List<MessagePiece> splitZAppLinks(String text) {
  final out = <MessagePiece>[];
  var at = 0;
  for (final m in _zappLink.allMatches(text)) {
    var raw = m.group(0)!;
    final tail = _trailing.firstMatch(raw);
    if (tail != null) raw = raw.substring(0, tail.start);
    final link = parseZAppLink(raw);
    if (link == null) continue;
    if (m.start > at) out.add(MessagePiece(text.substring(at, m.start)));
    out.add(MessagePiece(raw, link));
    at = m.start + raw.length;
  }
  if (at < text.length) out.add(MessagePiece(text.substring(at)));
  return out.isEmpty ? [MessagePiece(text)] : out;
}
