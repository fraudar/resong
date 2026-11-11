// language: Dart, file: lib/core/audio_tags.dart, target: any, runtime: resong app
// Gravador puro em Dart de tags ID3v2.3 (MP3) e átomos MP4/iTunes (M4A) com capa embutida.
import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

class AudioTags {
  const AudioTags._();

  /// Embute título, artistas, álbum, ano, comentário e capa em bytes `.mp3` ou `.m4a`.
  /// Para formatos sem suporte direto (ex.: `.webm`), devolve os bytes originais sem corromper.
  static Uint8List write({
    required Uint8List audioBytes,
    required String ext,
    required Track track,
    Uint8List? coverBytes,
  }) {
    final cleanExt = ext.toLowerCase().replaceAll('.', '');
    if (cleanExt == 'mp3' || _looksLikeMp3WithId3(audioBytes)) {
      return _writeId3v23(audioBytes, track: track, coverBytes: coverBytes);
    }
    if (cleanExt == 'm4a' || cleanExt == 'mp4' || _looksLikeMp4(audioBytes)) {
      return _writeMp4Tags(audioBytes, track: track, coverBytes: coverBytes);
    }
    return audioBytes;
  }

  static bool _looksLikeMp3WithId3(Uint8List b) =>
      b.length >= 3 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33;

  static bool _looksLikeMp4(Uint8List b) =>
      b.length >= 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70;

  static String _detectImageMime(Uint8List img) {
    if (img.length >= 4 && img[0] == 0x89 && img[1] == 0x50 && img[2] == 0x4E && img[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  // ------------------------------------------------------------------ MP3 (ID3v2.3)

  static Uint8List _writeId3v23(
    Uint8List input, {
    required Track track,
    Uint8List? coverBytes,
  }) {
    final audioStart = _id3BodyOffset(input);
    final rawFramesPayload = Uint8List.sublistView(input, audioStart);

    final frames = BytesBuilder(copy: false);
    if (track.title.trim().isNotEmpty) {
      frames.add(_id3TextFrame('TIT2', track.title.trim()));
    }
    if (track.artists.isNotEmpty) {
      frames.add(_id3TextFrame('TPE1', track.artists.join(', ')));
    }
    if ((track.album ?? '').trim().isNotEmpty) {
      frames.add(_id3TextFrame('TALB', track.album!.trim()));
    }
    final year = track.extra['year']?.toString().trim() ?? '';
    if (RegExp(r'^\d{4}$').hasMatch(year)) {
      frames.add(_id3TextFrame('TYER', year));
    }
    frames.add(_id3CommFrame('eng', 'baixado via resong'));
    if (coverBytes != null && coverBytes.length >= 64) {
      frames.add(_id3ApicFrame(coverBytes));
    }

    final frameBytes = frames.takeBytes();
    final out = BytesBuilder(copy: false)
      ..add(const [0x49, 0x44, 0x33, 0x03, 0x00, 0x00]) // "ID3" v2.3.0
      ..add(_encodeSyncSafe(frameBytes.length))
      ..add(frameBytes)
      ..add(rawFramesPayload);
    return out.takeBytes();
  }

  static int _id3BodyOffset(Uint8List b) {
    if (!_looksLikeMp3WithId3(b) || b.length < 10) return 0;
    final flags = b[5];
    final size = ((b[6] & 0x7F) << 21) | ((b[7] & 0x7F) << 14) | ((b[8] & 0x7F) << 7) | (b[9] & 0x7F);
    final hasFooter = (flags & 0x10) != 0;
    final end = 10 + size + (hasFooter ? 10 : 0);
    return end <= b.length ? end : 0;
  }

  static Uint8List _encodeSyncSafe(int n) => Uint8List.fromList([
        (n >> 21) & 0x7F,
        (n >> 14) & 0x7F,
        (n >> 7) & 0x7F,
        n & 0x7F,
      ]);

  static Uint8List _encodeU32Be(int n) => Uint8List.fromList([
        (n >> 24) & 0xFF,
        (n >> 16) & 0xFF,
        (n >> 8) & 0xFF,
        n & 0xFF,
      ]);

  static Uint8List _encodeUtf16LeWithBom(String text) {
    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xFE]);
    for (final unit in text.codeUnits) {
      out.addByte(unit & 0xFF);
      out.addByte((unit >> 8) & 0xFF);
    }
    return out.takeBytes();
  }

  static Uint8List _id3Frame(String id, Uint8List payload) {
    final out = BytesBuilder(copy: false)
      ..add(ascii.encode(id))
      ..add(_encodeU32Be(payload.length))
      ..add(const [0x00, 0x00])
      ..add(payload);
    return out.takeBytes();
  }

  static Uint8List _id3TextFrame(String id, String text) {
    final body = BytesBuilder(copy: false)
      ..addByte(0x01) // UTF-16 com BOM
      ..add(_encodeUtf16LeWithBom(text));
    return _id3Frame(id, body.takeBytes());
  }

  static Uint8List _id3CommFrame(String lang, String text) {
    final l = lang.padRight(3, ' ').substring(0, 3);
    final body = BytesBuilder(copy: false)
      ..addByte(0x01) // UTF-16 com BOM
      ..add(ascii.encode(l))
      ..add(const [0xFF, 0xFE, 0x00, 0x00]) // descrição vazia terminada em \0\0
      ..add(_encodeUtf16LeWithBom(text));
    return _id3Frame('COMM', body.takeBytes());
  }

  static Uint8List _id3ApicFrame(Uint8List img) {
    final mime = _detectImageMime(img);
    final body = BytesBuilder(copy: false)
      ..addByte(0x00) // Latin-1
      ..add(ascii.encode(mime))
      ..addByte(0x00)
      ..addByte(0x03) // Cover (front)
      ..addByte(0x00) // descrição vazia
      ..add(img);
    return _id3Frame('APIC', body.takeBytes());
  }

  // ------------------------------------------------------------------ MP4 / M4A (ISO BMFF)

  static Uint8List _writeMp4Tags(
    Uint8List input, {
    required Track track,
    Uint8List? coverBytes,
  }) {
    final boxes = _parseBoxes(input, 0, input.length);
    final moovIdx = boxes.indexWhere((b) => b.type == 'moov');
    if (moovIdx < 0) return input;

    final moov = boxes[moovIdx];
    final mdatIdx = boxes.indexWhere((b) => b.type == 'mdat');
    final moovBeforeMdat = mdatIdx >= 0 && moovIdx < mdatIdx;

    final moovChildren = _parseBoxes(input, moov.dataStart, moov.end);
    final ilst = _buildMp4Ilst(track: track, coverBytes: coverBytes);
    final meta = _buildMp4Meta(ilst);
    final udta = _buildMp4Udta(input, moovChildren, meta);

    // Primeira passagem para descobrir o tamanho exato do novo `moov`
    Uint8List assembleMoov(List<_Mp4Box> children, int chunkDelta) {
      final content = BytesBuilder(copy: false);
      var hadUdta = false;
      for (final child in children) {
        if (child.type == 'udta') {
          content.add(udta);
          hadUdta = true;
        } else if (child.type == 'trak' && chunkDelta != 0) {
          content.add(_shiftTrakChunkOffsets(input, child, chunkDelta));
        } else {
          content.add(Uint8List.sublistView(input, child.start, child.end));
        }
      }
      if (!hadUdta) {
        content.add(udta);
      }
      return _wrapBox('moov', content.takeBytes());
    }

    final initialMoov = assembleMoov(moovChildren, 0);
    final delta = initialMoov.length - (moov.end - moov.start);
    final finalMoov = (moovBeforeMdat && delta != 0) ? assembleMoov(moovChildren, delta) : initialMoov;

    final out = BytesBuilder(copy: false);
    for (var i = 0; i < boxes.length; i++) {
      if (i == moovIdx) {
        out.add(finalMoov);
      } else {
        out.add(Uint8List.sublistView(input, boxes[i].start, boxes[i].end));
      }
    }
    return out.takeBytes();
  }

  static Uint8List _buildMp4Udta(
    Uint8List input,
    List<_Mp4Box> moovChildren,
    Uint8List metaBox,
  ) {
    final udta = moovChildren.where((b) => b.type == 'udta').firstOrNull;
    final content = BytesBuilder(copy: false);
    if (udta != null) {
      final udtaChildren = _parseBoxes(input, udta.dataStart, udta.end);
      var replacedMeta = false;
      for (final c in udtaChildren) {
        if (c.type == 'meta') {
          content.add(metaBox);
          replacedMeta = true;
        } else {
          content.add(Uint8List.sublistView(input, c.start, c.end));
        }
      }
      if (!replacedMeta) content.add(metaBox);
    } else {
      content.add(metaBox);
    }
    return _wrapBox('udta', content.takeBytes());
  }

  static Uint8List _buildMp4Meta(Uint8List ilstBox) {
    // FullBox header (version + flags) + hdlr ('mdir'/'appl') + ilst
    final hdlrPayload = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x00, // version + flags
      0x00, 0x00, 0x00, 0x00, // pre_defined
      0x6D, 0x64, 0x69, 0x72, // handler_type = 'mdir'
      0x61, 0x70, 0x70, 0x6C, // manufacturer = 'appl'
      0x00, 0x00, 0x00, 0x00, // reserved
      0x00, 0x00, 0x00, 0x00, // reserved
      0x00, // name null-terminated
    ]);
    final body = BytesBuilder(copy: false)
      ..add(const [0x00, 0x00, 0x00, 0x00])
      ..add(_wrapBox('hdlr', hdlrPayload))
      ..add(ilstBox);
    return _wrapBox('meta', body.takeBytes());
  }

  static Uint8List _buildMp4Ilst({required Track track, Uint8List? coverBytes}) {
    final items = BytesBuilder(copy: false);
    void addTextAtom(List<int> tagBytes, String value) {
      final clean = value.trim();
      if (clean.isEmpty) return;
      final payload = Uint8List.fromList(utf8.encode(clean));
      final dataBox = _buildMp4DataBox(1, payload);
      items.add(_wrapRawTagBox(tagBytes, dataBox));
    }

    addTextAtom([0xA9, 0x6E, 0x61, 0x6D], track.title); // ©nam
    if (track.artists.isNotEmpty) {
      addTextAtom([0xA9, 0x41, 0x52, 0x54], track.artists.join(', ')); // ©ART
    }
    if (track.album != null) {
      addTextAtom([0xA9, 0x61, 0x6C, 0x62], track.album!); // ©alb
    }
    final year = track.extra['year']?.toString().trim() ?? '';
    if (year.isNotEmpty) {
      addTextAtom([0xA9, 0x64, 0x61, 0x79], year); // ©day
    }
    addTextAtom([0xA9, 0x63, 0x6D, 0x74], 'baixado via resong'); // ©cmt

    if (coverBytes != null && coverBytes.length >= 64) {
      final imgType = _detectImageMime(coverBytes) == 'image/png' ? 14 : 13;
      final dataBox = _buildMp4DataBox(imgType, coverBytes);
      items.add(_wrapRawTagBox(ascii.encode('covr'), dataBox));
    }

    return _wrapBox('ilst', items.takeBytes());
  }

  static Uint8List _buildMp4DataBox(int dataType, Uint8List value) {
    final body = BytesBuilder(copy: false)
      ..add(_encodeU32Be(dataType)) // version/type indicator
      ..add(const [0x00, 0x00, 0x00, 0x00]) // locale
      ..add(value);
    return _wrapBox('data', body.takeBytes());
  }

  static Uint8List _wrapBox(String type, Uint8List content) =>
      _wrapRawTagBox(ascii.encode(type), content);

  static Uint8List _wrapRawTagBox(List<int> tag4, Uint8List content) {
    final total = 8 + content.length;
    final out = BytesBuilder(copy: false)
      ..add(_encodeU32Be(total))
      ..add(tag4)
      ..add(content);
    return out.takeBytes();
  }

  static Uint8List _shiftTrakChunkOffsets(Uint8List input, _Mp4Box box, int delta) {
    if (box.type == 'stco') {
      final copy = Uint8List.fromList(Uint8List.sublistView(input, box.start, box.end));
      if (copy.length < 16) return copy;
      final bd = ByteData.sublistView(copy);
      final count = bd.getUint32(12);
      for (var i = 0; i < count && 16 + i * 4 + 4 <= copy.length; i++) {
        final cur = bd.getUint32(16 + i * 4);
        bd.setUint32(16 + i * 4, cur + delta);
      }
      return copy;
    }
    if (box.type == 'co64') {
      final copy = Uint8List.fromList(Uint8List.sublistView(input, box.start, box.end));
      if (copy.length < 16) return copy;
      final bd = ByteData.sublistView(copy);
      final count = bd.getUint32(12);
      for (var i = 0; i < count && 16 + i * 8 + 8 <= copy.length; i++) {
        final cur = bd.getUint64(16 + i * 8);
        bd.setUint64(16 + i * 8, cur + delta);
      }
      return copy;
    }
    if (box.type == 'trak' || box.type == 'mdia' || box.type == 'minf' || box.type == 'stbl') {
      final children = _parseBoxes(input, box.dataStart, box.end);
      final content = BytesBuilder(copy: false);
      for (final c in children) {
        content.add(_shiftTrakChunkOffsets(input, c, delta));
      }
      return _wrapBox(box.type, content.takeBytes());
    }
    return Uint8List.sublistView(input, box.start, box.end);
  }

  static List<_Mp4Box> _parseBoxes(Uint8List data, int start, int end) {
    final boxes = <_Mp4Box>[];
    var offset = start;
    final bd = ByteData.sublistView(data);
    while (offset + 8 <= end) {
      final size32 = bd.getUint32(offset);
      final type = latin1.decode(Uint8List.sublistView(data, offset + 4, offset + 8));
      var headerLen = 8;
      int boxSize;
      if (size32 == 1) {
        if (offset + 16 > end) break;
        boxSize = bd.getUint64(offset + 8);
        headerLen = 16;
      } else if (size32 == 0) {
        boxSize = end - offset;
      } else {
        boxSize = size32;
      }
      if (boxSize < headerLen || offset + boxSize > end) break;
      boxes.add(_Mp4Box(
        type: type,
        start: offset,
        dataStart: offset + headerLen,
        end: offset + boxSize,
      ));
      offset += boxSize;
    }
    return boxes;
  }
}

class _Mp4Box {
  const _Mp4Box({
    required this.type,
    required this.start,
    required this.dataStart,
    required this.end,
  });

  final String type;
  final int start;
  final int dataStart;
  final int end;
}
