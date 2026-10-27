import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'zend_modal.dart';
import 'zend_tokens.dart';

/// GIF notes work like emoji notes: the payment note carries a compact
/// reference (`gif:<giphy id>`, ~25 chars, so it fits existing note limits and
/// needs no backend change) and every surface that shows an emoji tile shows
/// the GIF instead.
///
/// Search needs a GIPHY key passed at build time:
///   flutter build ... --dart-define=GIPHY_API_KEY=xxx
/// Without one the GIF button is hidden; existing GIF notes still render,
/// since media URLs don't need a key.
const _giphyKey = String.fromEnvironment('GIPHY_API_KEY');
bool get gifSearchEnabled => _giphyKey.isNotEmpty;

const _prefix = 'gif:';

String? gifIdFromNote(String? note) {
  final n = note?.trim() ?? '';
  if (!n.startsWith(_prefix)) return null;
  final id = n.substring(_prefix.length);
  // Ids are alphanumeric; anything else is not ours and is never fetched.
  return RegExp(r'^[A-Za-z0-9]{4,40}$').hasMatch(id) ? id : null;
}

String gifNote(String id) => '$_prefix$id';

String _media(String id, {bool small = false}) =>
    'https://media.giphy.com/media/$id/${small ? '200w' : 'giphy'}.gif';

/// A GIF note on a rounded tile, the GIF counterpart of `ZendEmojiTile`.
class ZendGifTile extends StatelessWidget {
  const ZendGifTile(this.id, {super.key, this.height = 120});

  final String id;
  final double height;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Semantics(
      image: true,
      label: 'GIF note',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZendRadii.card),
        child: Container(
          height: height,
          constraints: BoxConstraints(maxWidth: height * 1.8),
          color: zt.bgElevated,
          child: CachedNetworkImage(
            imageUrl: _media(id, small: height <= 140),
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Opens a GIPHY search sheet; returns the chosen GIF id.
Future<String?> showGifPicker(BuildContext context) {
  return showZendModalSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GifPicker(),
  );
}

class _GifPicker extends StatefulWidget {
  const _GifPicker();

  @override
  State<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<_GifPicker> {
  final _dio = Dio(BaseOptions(baseUrl: 'https://api.giphy.com/v1/gifs'));
  List<String> _ids = [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final r = await _dio.get(
        q.trim().isEmpty ? '/trending' : '/search',
        queryParameters: {
          'api_key': _giphyKey,
          'q': q.trim(),
          'limit': 24,
          'rating': 'pg',
        },
      );
      if (seq != _seq || !mounted) return;
      final data = (r.data['data'] as List).cast<Map<String, dynamic>>();
      setState(() => _ids = [for (final g in data) g['id'] as String]);
    } catch (_) {
      if (seq == _seq && mounted) setState(() => _ids = []);
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final h = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              TextField(
                autofocus: true,
                onChanged: _load,
                decoration: InputDecoration(
                  hintText: 'Search GIFs',
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading && _ids.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                        itemCount: _ids.length,
                        itemBuilder: (context, i) => InkWell(
                          onTap: () => Navigator.of(context).pop(_ids[i]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(ZendRadii.chip),
                            child: CachedNetworkImage(
                              imageUrl: _media(_ids[i], small: true),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
              ),
              Text(
                'Powered by GIPHY',
                style: ZendTextStyles.micro.copyWith(color: zt.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
