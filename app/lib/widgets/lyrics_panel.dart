// language: Dart, file: lib/widgets/lyrics_panel.dart, target: mobile + desktop + web, runtime: resong app
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/lyrics_cache.dart';
import '../state/providers.dart';
import 'glass.dart';

/// Painel completo de letras (Sincronizada, Karaokê palavra-a-palavra, Vocal de fundo, Romanização e Tradução).
/// Reutilizado no bottom sheet mobile e no painel direito dividido do modo Desktop (estilo Sonora).
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({
    super.key,
    required this.track,
    required this.accent,
    this.scrollController,
    this.desktopStyle = false,
  });

  final Track track;
  final Color accent;
  final ScrollController? scrollController;
  final bool desktopStyle;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  late final ScrollController _internalScroll = ScrollController();
  ScrollController get _scrollController => widget.scrollController ?? _internalScroll;

  Lyrics? _lyrics;
  bool _loading = true;
  String? _error;
  late String _loadedTrackId;

  bool _showTranslation = false;
  bool _translating = false;
  bool _karaokeMode = true;
  bool _showBackground = true;
  bool _showRomanization = false;
  bool _romanizing = false;
  final Map<String, List<String>> _translatedCache = {};
  final Map<String, List<String>> _romanizedCache = {};

  @override
  void initState() {
    super.initState();
    _loadedTrackId = widget.track.id;
    _loadForTrack(widget.track);
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _loadForTrack(widget.track);
    }
  }

  @override
  void dispose() {
    _internalScroll.dispose();
    super.dispose();
  }

  void _loadForTrack(Track track) {
    _loadedTrackId = track.id;
    _showTranslation = _translatedCache.containsKey(track.id);
    _showRomanization = _romanizedCache.containsKey(track.id);
    _translating = false;
    _romanizing = false;
    final cached = LyricsCache.instance.getCached(track.id);
    if (LyricsCache.instance.hasCached(track.id)) {
      _lyrics = cached;
      _loading = false;
      _error = cached == null ? 'Letras não encontradas' : null;
    } else {
      _lyrics = null;
      _loading = true;
      _error = null;
      _fetch(track);
    }
  }

  Future<void> _fetch(Track track) async {
    try {
      final data = await LyricsCache.instance.getOrFetch(track);
      if (!mounted || _loadedTrackId != track.id) return;
      setState(() {
        _lyrics = data;
        _loading = false;
        _error = data == null ? 'Letras não encontradas' : null;
      });
    } catch (_) {
      if (!mounted || _loadedTrackId != track.id) return;
      setState(() {
        _loading = false;
        _error = 'Falha ao buscar letras';
      });
    }
  }

  Future<void> _toggleTranslate(Track activeTrack) async {
    if (_showTranslation) {
      setState(() => _showTranslation = false);
      return;
    }
    if (_translatedCache.containsKey(activeTrack.id)) {
      setState(() => _showTranslation = true);
      return;
    }
    final lyrics = _lyrics;
    if (lyrics == null || _translating) return;

    final sourceLines = lyrics.synced != null
        ? [for (final l in parseLrc(lyrics.synced!)) l.text]
        : (lyrics.plain ?? '').split('\n');
    if (sourceLines.isEmpty) return;

    setState(() => _translating = true);
    try {
      final translated = await Api.instance.translateLyrics(sourceLines, target: 'pt');
      if (!mounted) return;
      _translatedCache[activeTrack.id] = translated.lines;
      if (translated.romanized.isNotEmpty && !_romanizedCache.containsKey(activeTrack.id)) {
        _romanizedCache[activeTrack.id] = translated.romanized;
      }
      setState(() {
        _translating = false;
        _showTranslation = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _translating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível traduzir a letra agora')),
      );
    }
  }

  Future<void> _toggleRomanize(Track activeTrack) async {
    if (_showRomanization) {
      setState(() => _showRomanization = false);
      return;
    }
    final lyrics = _lyrics;
    if (lyrics == null || _romanizing) return;

    final richLines = resolveRichLines(lyrics);
    if (richLines.isNotEmpty && richLines.any((l) => (l.romanized ?? '').trim().isNotEmpty)) {
      _romanizedCache[activeTrack.id] = [for (final l in richLines) l.romanized ?? ''];
      setState(() => _showRomanization = true);
      return;
    }

    if (_romanizedCache.containsKey(activeTrack.id)) {
      setState(() => _showRomanization = true);
      return;
    }

    final sourceLines = richLines.isNotEmpty
        ? [for (final l in richLines) l.text]
        : (lyrics.plain ?? '').split('\n');
    if (sourceLines.isEmpty) return;

    setState(() => _romanizing = true);
    try {
      final res = await Api.instance.romanizeLyrics(sourceLines);
      if (!mounted) return;
      final out = [
        for (var i = 0; i < sourceLines.length; i++)
          (i < res.lines.length && res.lines[i].trim().isNotEmpty && res.lines[i].trim() != sourceLines[i].trim())
              ? res.lines[i]
              : (hasNonLatinScript(sourceLines[i]) ? fallbackRomanize(sourceLines[i]) : ''),
      ];
      _romanizedCache[activeTrack.id] = out;
      setState(() {
        _romanizing = false;
        _showRomanization = true;
      });
    } catch (_) {
      if (!mounted) return;
      _romanizedCache[activeTrack.id] = [
        for (final line in sourceLines) hasNonLatinScript(line) ? fallbackRomanize(line) : '',
      ];
      setState(() {
        _romanizing = false;
        _showRomanization = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.accent;
    final activeTrack = widget.track;

    Widget content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: colors.textTertiary)))
            : (_lyrics?.synced != null
                ? _SyncedLyricsBody(
                    track: activeTrack,
                    lyrics: _lyrics!,
                    karaokeMode: _karaokeMode,
                    showBackground: _showBackground,
                    romanizedLines: _showRomanization ? _romanizedCache[activeTrack.id] : null,
                    translatedLines: _showTranslation ? _translatedCache[activeTrack.id] : null,
                    accent: accent,
                    desktopStyle: widget.desktopStyle,
                    scrollController: _scrollController,
                  )
                : _PlainLyricsBody(
                    text: _lyrics?.plain ?? '',
                    showBackground: _showBackground,
                    romanizedLines: _showRomanization ? _romanizedCache[activeTrack.id] : null,
                    translatedLines: _showTranslation ? _translatedCache[activeTrack.id] : null,
                    accent: accent,
                    desktopStyle: widget.desktopStyle,
                    scrollController: _scrollController,
                  ));

    if (widget.desktopStyle && !_loading && _error == null) {
      content = ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.08, 0.86, 1.0],
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: content,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lyrics != null && !_loading) ...[
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (_lyrics!.synced != null) ...[
                  LyricsModeChip(
                    label: _karaokeMode ? 'Karaokê' : 'Sincronizada',
                    active: true,
                    accent: accent,
                    onTap: () => setState(() => _karaokeMode = !_karaokeMode),
                  ),
                  const SizedBox(width: 7),
                ],
                LyricsModeChip(
                  label: 'Vocal de fundo',
                  active: _showBackground,
                  accent: accent,
                  onTap: () => setState(() => _showBackground = !_showBackground),
                ),
                const SizedBox(width: 7),
                LyricsModeChip(
                  label: _romanizing ? 'Romanizando…' : 'Romanização',
                  active: _showRomanization,
                  accent: accent,
                  onTap: _romanizing ? null : () => _toggleRomanize(activeTrack),
                ),
                const SizedBox(width: 7),
                LyricsModeChip(
                  label: _translating ? 'Traduzindo…' : 'Traduzir',
                  active: _showTranslation,
                  accent: accent,
                  icon: SolarIconsBold.global,
                  onTap: _translating ? null : () => _toggleTranslate(activeTrack),
                ),
              ],
            ),
          ),
          if (_translating || _romanizing) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(minHeight: 2, color: accent, backgroundColor: Colors.transparent),
          ] else
            const SizedBox(height: 6),
        ],
        Expanded(child: content),
      ],
    );
  }
}

class LyricsModeChip extends StatelessWidget {
  const LyricsModeChip({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool active;
  final Color accent;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: active
              ? accent.withValues(alpha: colors.isDark ? 0.24 : 0.16)
              : (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.65) : colors.stroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: active ? (colors.isDark ? Colors.white : accent) : colors.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? (colors.isDark ? Colors.white : accent) : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainLyricsBody extends StatelessWidget {
  const _PlainLyricsBody({
    required this.text,
    required this.scrollController,
    this.showBackground = true,
    this.desktopStyle = false,
    this.romanizedLines,
    this.translatedLines,
    this.accent,
  });

  final String text;
  final ScrollController scrollController;
  final bool showBackground;
  final bool desktopStyle;
  final List<String>? romanizedLines;
  final List<String>? translatedLines;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = text.split('\n');
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.only(top: desktopStyle ? 28 : 12, bottom: desktopStyle ? 88 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (lines[i].trim().isEmpty)
              const SizedBox(height: 14)
            else
              Builder(
                builder: (context) {
                  final split = splitBackgroundVocals(lines[i]);
                  if (split.isBg && !showBackground) return const SizedBox.shrink();
                  final mainText = split.isBg
                      ? ''
                      : (split.bg != null ? split.lead : lines[i]);
                  final bgText = showBackground ? (split.isBg ? lines[i] : split.bg) : null;
                  final rom = romanizedLines != null && i < romanizedLines!.length
                      ? romanizedLines![i].trim()
                      : '';
                  final tr = translatedLines != null && i < translatedLines!.length
                      ? translatedLines![i].trim()
                      : '';
                  return Padding(
                    padding: EdgeInsets.only(bottom: desktopStyle ? 16 : 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mainText.isNotEmpty)
                          Text(
                            mainText,
                            style: TextStyle(
                              fontSize: desktopStyle ? 22 : 17,
                              height: 1.44,
                              fontWeight: FontWeight.w600,
                              color: desktopStyle ? colors.textSecondary : colors.textPrimary,
                            ),
                          ),
                        if (bgText != null && bgText.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: mainText.isNotEmpty ? 3 : 0, left: 10),
                            child: Text(
                              bgText,
                              style: TextStyle(
                                fontSize: desktopStyle ? 17 : 14.5,
                                height: 1.36,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        if (rom.isNotEmpty && rom != lines[i].trim())
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              rom,
                              style: TextStyle(
                                fontSize: desktopStyle ? 15 : 13.5,
                                fontStyle: FontStyle.italic,
                                color: (accent ?? colors.accent).withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        if (tr.isNotEmpty && tr != lines[i].trim())
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              tr,
                              style: TextStyle(
                                fontSize: desktopStyle ? 16 : 14.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: (accent ?? colors.accent).withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _SyncedLyricsBody extends ConsumerStatefulWidget {
  const _SyncedLyricsBody({
    required this.track,
    required this.lyrics,
    required this.accent,
    required this.scrollController,
    this.karaokeMode = true,
    this.showBackground = true,
    this.desktopStyle = false,
    this.romanizedLines,
    this.translatedLines,
  });

  final Track track;
  final Lyrics lyrics;
  final Color accent;
  final ScrollController scrollController;
  final bool karaokeMode;
  final bool showBackground;
  final bool desktopStyle;
  final List<String>? romanizedLines;
  final List<String>? translatedLines;

  @override
  ConsumerState<_SyncedLyricsBody> createState() => _SyncedLyricsBodyState();
}

class _SyncedLyricsBodyState extends ConsumerState<_SyncedLyricsBody> {
  late List<LyricRichLine> _lines;
  late List<GlobalKey> _lineKeys;
  bool _autoScroll = true;
  int _lastScrolledIndex = -1;
  Timer? _resumeTimer;
  Timer? _karaokeTimer;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initLines();
    _syncKaraokeTimer();
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.lyrics.synced != widget.lyrics.synced ||
        oldWidget.lyrics.lines.length != widget.lyrics.lines.length) {
      _lastScrolledIndex = -1;
      _autoScroll = true;
      _initLines();
    }
    if (oldWidget.karaokeMode != widget.karaokeMode) {
      _syncKaraokeTimer();
    }
  }

  void _initLines() {
    _lines = resolveRichLines(widget.lyrics);
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
  }

  void _syncKaraokeTimer() {
    _karaokeTimer?.cancel();
    if (!widget.karaokeMode) return;
    _karaokeTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted) return;
      final playing = ref.read(isPlayingProvider);
      if (playing) setState(() {});
    });
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _karaokeTimer?.cancel();
    super.dispose();
  }

  void _scrollToLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    final ctx = _lineKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.33,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _onUserScroll() {
    if (_autoScroll) {
      setState(() => _autoScroll = false);
    }
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _autoScroll = true);
      if (_lastScrolledIndex >= 0) _scrollToLine(_lastScrolledIndex);
    });
  }

  Future<void> _shareLine(LyricRichLine line) async {
    final quote = '“${line.text}” — ${widget.track.title}, ${widget.track.artistLine}';
    await Clipboard.setData(ClipboardData(text: quote));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trecho da letra copiado')),
      );
    }
  }

  Widget _buildKaraokeLine({
    required LyricRichLine line,
    required int lineIndex,
    required int activeIndex,
    required int posMs,
    required bool isBgOnly,
    required TextStyle baseStyle,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final text = isBgOnly
        ? (line.bgText ?? line.text)
        : (line.leadText?.isNotEmpty == true ? line.leadText! : line.text);

    if (lineIndex != activeIndex || !widget.karaokeMode) {
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: baseStyle.copyWith(color: lineIndex == activeIndex ? activeColor : inactiveColor),
        child: Text(text),
      );
    }

    final nextAt = lineIndex + 1 < _lines.length
        ? _lines[lineIndex + 1].atMs
        : (line.durMs != null ? line.atMs + line.durMs! : line.atMs + 4000);
    final tokens = wordsForKaraokeText(
      text,
      line.words,
      line.atMs,
      nextAt,
      filterBg: !isBgOnly && (line.bgText ?? '').isNotEmpty,
    );
    if (tokens.isEmpty) {
      return Text(text, style: baseStyle.copyWith(color: activeColor));
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          for (final w in tokens)
            TextSpan(
              text: w.text,
              style: TextStyle(
                color: () {
                  if (posMs >= w.atMs + w.durMs) return activeColor;
                  if (posMs <= w.atMs) return activeColor.withValues(alpha: 0.34);
                  final t = ((posMs - w.atMs) / w.durMs.clamp(1, 6000)).clamp(0.0, 1.0);
                  return Color.lerp(activeColor.withValues(alpha: 0.34), activeColor, t)!;
                }(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final handler = ref.watch(handlerProvider);
    final playing = ref.watch(isPlayingProvider);

    return StreamBuilder<Duration>(
      stream: handler.player.positionStream,
      initialData: handler.player.position,
      builder: (context, snapshot) {
        final rawPos = snapshot.data ?? Duration.zero;
        if (rawPos != _lastPos) {
          _lastPos = rawPos;
          _lastPosAt = DateTime.now();
        }
        final interpMs = playing && widget.karaokeMode
            ? DateTime.now().difference(_lastPosAt).inMilliseconds.clamp(0, 260)
            : 0;
        final pos = rawPos + Duration(milliseconds: interpMs);
        final posMs = pos.inMilliseconds;

        var active = -1;
        for (var i = 0; i < _lines.length; i++) {
          if (_lines[i].atMs <= posMs) {
            active = i;
          } else {
            break;
          }
        }
        if (active != _lastScrolledIndex && active >= 0) {
          _lastScrolledIndex = active;
          if (_autoScroll) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autoScroll) _scrollToLine(active);
            });
          }
        }

        return Stack(
          children: [
            NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.direction != ScrollDirection.idle) {
                  _onUserScroll();
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: EdgeInsets.only(top: widget.desktopStyle ? 28 : 12, bottom: widget.desktopStyle ? 96 : 72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _lines.length; i++)
                      if (!_lines[i].isBackground || widget.showBackground)
                        Semantics(
                          button: true,
                          label: _lines[i].text,
                          child: InkWell(
                            key: _lineKeys[i],
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setState(() => _autoScroll = true);
                              handler.seek(Duration(milliseconds: _lines[i].atMs));
                            },
                            onLongPress: () => _shareLine(_lines[i]),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                _lines[i].isBackground ? 16 : 6,
                                _lines[i].isBackground ? 4 : (widget.desktopStyle ? 11 : 9),
                                6,
                                _lines[i].isBackground ? 6 : (widget.desktopStyle ? 11 : 9),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildKaraokeLine(
                                          line: _lines[i],
                                          lineIndex: i,
                                          activeIndex: active,
                                          posMs: posMs,
                                          isBgOnly: _lines[i].isBackground,
                                          baseStyle: TextStyle(
                                            fontSize: _lines[i].isBackground
                                                ? (i == active ? (widget.desktopStyle ? 19 : 17.5) : (widget.desktopStyle ? 16.5 : 15))
                                                : (i == active ? (widget.desktopStyle ? 25 : 22) : (widget.desktopStyle ? 21 : 17)),
                                            height: 1.38,
                                            fontStyle: _lines[i].isBackground ? FontStyle.italic : FontStyle.normal,
                                            fontWeight: _lines[i].isBackground
                                                ? FontWeight.w500
                                                : (i == active ? FontWeight.w700 : FontWeight.w600),
                                          ),
                                          activeColor: _lines[i].isBackground
                                              ? widget.accent
                                              : (colors.isDark ? Colors.white : widget.accent),
                                          inactiveColor: _lines[i].isBackground
                                              ? colors.textTertiary.withValues(alpha: 0.72)
                                              : colors.textTertiary,
                                        ),
                                        if (widget.showBackground &&
                                            !_lines[i].isBackground &&
                                            (_lines[i].bgText ?? '').isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3, left: 10),
                                            child: Text(
                                              _lines[i].bgText!,
                                              style: TextStyle(
                                                fontSize: i == active ? 16 : 14,
                                                fontStyle: FontStyle.italic,
                                                fontWeight: i == active ? FontWeight.w600 : FontWeight.w400,
                                                color: i == active
                                                    ? widget.accent.withValues(alpha: 0.92)
                                                    : colors.textTertiary.withValues(alpha: 0.68),
                                              ),
                                            ),
                                          ),
                                        if (widget.romanizedLines != null &&
                                            i < widget.romanizedLines!.length &&
                                            widget.romanizedLines![i].trim().isNotEmpty &&
                                            widget.romanizedLines![i].trim() != _lines[i].text.trim())
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(
                                              widget.romanizedLines![i],
                                              style: TextStyle(
                                                fontSize: i == active ? 15.5 : 13.5,
                                                fontStyle: FontStyle.italic,
                                                height: 1.3,
                                                color: i == active
                                                    ? widget.accent.withValues(alpha: 0.95)
                                                    : colors.textTertiary.withValues(alpha: 0.75),
                                              ),
                                            ),
                                          ),
                                        if (widget.translatedLines != null &&
                                            i < widget.translatedLines!.length &&
                                            widget.translatedLines![i].trim().isNotEmpty &&
                                            widget.translatedLines![i].trim() != _lines[i].text.trim())
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: AnimatedDefaultTextStyle(
                                              duration: const Duration(milliseconds: 220),
                                              style: TextStyle(
                                                fontSize: i == active ? 16 : 14,
                                                height: 1.32,
                                                fontWeight: i == active ? FontWeight.w600 : FontWeight.w400,
                                                color: i == active
                                                    ? widget.accent
                                                    : colors.textTertiary.withValues(alpha: 0.72),
                                              ),
                                              child: Text(widget.translatedLines![i]),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (i == active) ...[
                                    const SizedBox(width: 6),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 17,
                                      tooltip: 'Compartilhar trecho',
                                      icon: Icon(SolarIconsBold.share, color: widget.accent),
                                      onPressed: () => _shareLine(_lines[i]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            if (!_autoScroll)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: GlassSurface(
                    borderRadius: BorderRadius.circular(22),
                    blur: 20,
                    tint: widget.accent,
                    tintStrength: 0.25,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        _resumeTimer?.cancel();
                        setState(() => _autoScroll = true);
                        _scrollToLine(active >= 0 ? active : 0);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(SolarIconsBold.musicNote, size: 15, color: widget.accent),
                            const SizedBox(width: 7),
                            Text(
                              'Voltar pra linha atual',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
