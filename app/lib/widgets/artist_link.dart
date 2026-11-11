// language: Dart, file: lib/widgets/artist_link.dart, target: mobile + desktop + web, runtime: resong app
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../screens/detail_screen.dart';

/// Exibe o nome do artista (ou múltiplos separados por vírgula) clicável para abrir o perfil do artista.
class ArtistTextLink extends StatefulWidget {
  const ArtistTextLink({
    super.key,
    required this.track,
    required this.style,
    this.textAlign = TextAlign.start,
    this.suffix,
    this.onOpenArtist,
  });

  final Track track;
  final TextStyle style;
  final TextAlign textAlign;
  final String? suffix;
  final void Function(String artistName)? onOpenArtist;

  @override
  State<ArtistTextLink> createState() => _ArtistTextLinkState();
}

class _ArtistTextLinkState extends State<ArtistTextLink> {
  final List<TapGestureRecognizer> _recognizers = [];
  bool _hovered = false;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _rebuildRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _rebuildRecognizers();
    final artists = widget.track.artists.where((a) => a.trim().isNotEmpty).toList();
    if (artists.isEmpty) {
      final fallback = [widget.track.artistLine, if (widget.suffix != null) widget.suffix!].join(' • ');
      return Text(
        fallback,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
        style: widget.style,
      );
    }

    final baseStyle = widget.style.copyWith(
      decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
      decorationColor: widget.style.color,
    );

    final spans = <InlineSpan>[];
    for (var i = 0; i < artists.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: ', ', style: widget.style));
      }
      final name = artists[i].trim();
      final rec = TapGestureRecognizer()
        ..onTap = () {
          if (widget.onOpenArtist != null) {
            widget.onOpenArtist!(name);
          } else {
            DetailScreen.openArtistForTrack(context, widget.track, artistName: name);
          }
        };
      _recognizers.add(rec);
      spans.add(TextSpan(text: name, style: baseStyle, recognizer: rec));
    }
    if (widget.suffix != null && widget.suffix!.isNotEmpty) {
      spans.add(TextSpan(text: ' • ${widget.suffix}', style: widget.style));
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
      ),
    );
  }
}
