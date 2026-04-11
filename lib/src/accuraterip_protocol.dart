/// AccurateRip wire protocol: URL builder and binary response parser.
///
/// These are pure functions — they never touch the network. Use them
/// directly if you want full control over the HTTP layer, or use the
/// `AccurateRipClient` convenience wrapper in `io/accuraterip_client.dart`.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:typed_data';

import 'accuraterip_disc_id.dart';
import 'accuraterip_models.dart';

/// Build the AccurateRip HTTP lookup [Uri] for [id].
///
/// The URL has the shape
/// `http://www.accuraterip.com/accuraterip/<a>/<b>/<c>/dBAR-<nnn>-<d1>-<d2>-<cddb>.bin`
/// where `<a>`, `<b>`, `<c>` are the last 1, 2, and 3 hexadecimal
/// digits of [AccurateRipDiscId.discId1], `<nnn>` is the zero-padded
/// track count, and `<d1>`, `<d2>`, `<cddb>` are the 8-digit
/// hexadecimal representations of the three disc ID fields.
///
/// The AccurateRip database is served over plain HTTP; this builder
/// does not force HTTPS. Consumers concerned with transport
/// security should wrap the fetcher.
Uri buildAccurateRipUrl(AccurateRipDiscId id) {
  final hex1 = id.discId1.toRadixString(16).padLeft(8, '0');
  final hex2 = id.discId2.toRadixString(16).padLeft(8, '0');
  final hexCddb = id.cddbDiscId.toRadixString(16).padLeft(8, '0');
  final tc = id.trackCount.toString().padLeft(3, '0');

  final a = hex1[7];
  final b = hex1.substring(6, 8);
  final c = hex1.substring(5, 8);

  return Uri.parse(
    'http://www.accuraterip.com/accuraterip/$a/$b/$c/'
    'dBAR-$tc-$hex1-$hex2-$hexCddb.bin',
  );
}

/// Parse a raw AccurateRip database response body into an
/// [AccurateRipDiscResult], or return `null` when [bytes] is empty
/// or structurally invalid.
///
/// An AccurateRip response is a concatenation of *chunks*, where
/// each chunk represents one pressing of the same disc:
///
/// ```text
/// chunk := trackCount : u8
///       || discId1    : u32 little-endian
///       || discId2    : u32 little-endian
///       || cddbDiscId : u32 little-endian
///       || (confidence : u8 || crc : u32 LE || frame450Crc : u32 LE) × trackCount
/// ```
///
/// Note: each entry carries **one** primary [AccurateRipEntry.crc]
/// (which the server stores as whatever the submitting ripper sent
/// — v1 or v2, the client cannot tell) plus a secondary
/// [AccurateRipEntry.frame450Crc] over the first 450 frames used
/// for drive-offset verification. There is no separate v1/v2 pair
/// per entry; verification is done by trying the locally computed
/// v1 and v2 against the single [AccurateRipEntry.crc] via
/// [AccurateRipEntry.matches].
///
/// Entries from every chunk are concatenated per track number
/// (1-based) and returned in ascending order. Chunks whose
/// declared `trackCount` exceeds the remaining bytes are silently
/// truncated.
AccurateRipDiscResult? parseAccurateRipResponse(Uint8List bytes) {
  if (bytes.isEmpty) return null;

  final trackEntries = <int, List<AccurateRipEntry>>{};

  var offset = 0;
  while (offset < bytes.length) {
    // 13-byte chunk header: trackCount (1) + discId1 (4) + discId2 (4)
    // + cddbDiscId (4). We don't re-verify the IDs here; the caller
    // already knows which disc they asked about.
    if (offset + 13 > bytes.length) break;

    final chunkTrackCount = bytes[offset];
    offset += 1;
    offset += 12; // skip discId1, discId2, cddbDiscId

    final trackDataSize = chunkTrackCount * 9;
    if (offset + trackDataSize > bytes.length) break;

    for (var t = 0; t < chunkTrackCount; t++) {
      final confidence = bytes[offset];
      offset += 1;

      final crc = _readUint32LE(bytes, offset);
      offset += 4;

      final frame450Crc = _readUint32LE(bytes, offset);
      offset += 4;

      final trackNumber = t + 1;
      trackEntries.putIfAbsent(trackNumber, () => <AccurateRipEntry>[]).add(
            AccurateRipEntry(
              confidence: confidence,
              crc: crc,
              frame450Crc: frame450Crc,
            ),
          );
    }
  }

  if (trackEntries.isEmpty) return null;

  final tracks = trackEntries.entries
      .map((e) => AccurateRipTrackResult(
            trackNumber: e.key,
            entries: e.value,
          ))
      .toList()
    ..sort((a, b) => a.trackNumber.compareTo(b.trackNumber));

  return AccurateRipDiscResult(tracks: tracks);
}

int _readUint32LE(Uint8List data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
