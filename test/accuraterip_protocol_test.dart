import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

/// Build a single AccurateRip response chunk as bytes.
Uint8List buildChunk({
  required int discId1,
  required int discId2,
  required int cddbDiscId,
  required List<({int confidence, int crc, int frame450Crc})> tracks,
}) {
  final builder = BytesBuilder();
  builder.addByte(tracks.length);
  builder.add(_uint32LE(discId1));
  builder.add(_uint32LE(discId2));
  builder.add(_uint32LE(cddbDiscId));
  for (final t in tracks) {
    builder.addByte(t.confidence);
    builder.add(_uint32LE(t.crc));
    builder.add(_uint32LE(t.frame450Crc));
  }
  return builder.toBytes();
}

List<int> _uint32LE(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

void main() {
  group('buildAccurateRipUrl', () {
    test('produces the three-component hex path from discId1', () {
      const id = AccurateRipDiscId(
        discId1: 0x0A1B2C3D,
        discId2: 0x11223344,
        cddbDiscId: 0x55667788,
        trackCount: 12,
      );

      final uri = buildAccurateRipUrl(id);

      expect(uri.scheme, equals('http'));
      expect(uri.host, equals('www.accuraterip.com'));
      expect(
        uri.path,
        equals(
          '/accuraterip/d/3d/c3d/dBAR-012-0a1b2c3d-11223344-55667788.bin',
        ),
      );
    });

    test('pads track count to three digits', () {
      const id = AccurateRipDiscId(
        discId1: 0x00000001,
        discId2: 0x00000002,
        cddbDiscId: 0x00000003,
        trackCount: 5,
      );

      expect(
        buildAccurateRipUrl(id).path,
        equals(
          '/accuraterip/1/01/001/dBAR-005-00000001-00000002-00000003.bin',
        ),
      );
    });
  });

  group('parseAccurateRipResponse', () {
    test('returns null for empty bytes', () {
      expect(parseAccurateRipResponse(Uint8List(0)), isNull);
    });

    test('decodes a single-chunk, two-track response', () {
      final bytes = buildChunk(
        discId1: 0x0A1B2C3D,
        discId2: 0x11223344,
        cddbDiscId: 0x55667788,
        tracks: const [
          (confidence: 42, crc: 0xDEADBEEF, frame450Crc: 0xCAFEBABE),
          (confidence: 17, crc: 0x11111111, frame450Crc: 0x22222222),
        ],
      );

      final result = parseAccurateRipResponse(bytes);

      expect(result, isNotNull);
      expect(result!.tracks, hasLength(2));

      expect(result.tracks[0].trackNumber, equals(1));
      expect(result.tracks[0].entries, hasLength(1));
      expect(result.tracks[0].entries.single.confidence, equals(42));
      expect(result.tracks[0].entries.single.crc, equals(0xDEADBEEF));
      expect(result.tracks[0].entries.single.frame450Crc, equals(0xCAFEBABE));

      expect(result.tracks[1].trackNumber, equals(2));
      expect(result.tracks[1].entries.single.crc, equals(0x11111111));
    });

    test('concatenates entries across multiple chunks per track number', () {
      // Two pressings of the same 2-track disc.
      final pressingA = buildChunk(
        discId1: 0xAAAAAAAA,
        discId2: 0,
        cddbDiscId: 0,
        tracks: const [
          (confidence: 50, crc: 0x11111111, frame450Crc: 0x22222222),
          (confidence: 50, crc: 0x33333333, frame450Crc: 0x44444444),
        ],
      );
      final pressingB = buildChunk(
        discId1: 0xBBBBBBBB,
        discId2: 0,
        cddbDiscId: 0,
        tracks: const [
          (confidence: 10, crc: 0xAAAAAAAA, frame450Crc: 0xBBBBBBBB),
          (confidence: 10, crc: 0xCCCCCCCC, frame450Crc: 0xDDDDDDDD),
        ],
      );

      final combined = Uint8List.fromList([...pressingA, ...pressingB]);
      final result = parseAccurateRipResponse(combined);

      expect(result, isNotNull);
      expect(result!.tracks, hasLength(2));

      expect(result.tracks[0].trackNumber, equals(1));
      expect(result.tracks[0].entries, hasLength(2));
      expect(
        result.tracks[0].entries.map((e) => e.crc),
        equals([0x11111111, 0xAAAAAAAA]),
      );

      expect(result.tracks[1].trackNumber, equals(2));
      expect(result.tracks[1].entries, hasLength(2));
      expect(
        result.tracks[1].entries.map((e) => e.frame450Crc),
        equals([0x44444444, 0xDDDDDDDD]),
      );
    });

    test('returns null when bytes are too short for even one chunk header', () {
      expect(parseAccurateRipResponse(Uint8List(5)), isNull);
    });

    test('tolerates a truncated trailing chunk without crashing', () {
      final good = buildChunk(
        discId1: 1,
        discId2: 2,
        cddbDiscId: 3,
        tracks: const [(confidence: 9, crc: 0xABCD, frame450Crc: 0xDCBA)],
      );
      // Append a truncated chunk header (5 bytes).
      final truncated =
          Uint8List.fromList([...good, 0x02, 0x00, 0x00, 0x00, 0x00]);

      final result = parseAccurateRipResponse(truncated);

      expect(result, isNotNull);
      expect(result!.tracks, hasLength(1));
      expect(result.tracks.single.entries.single.crc, equals(0xABCD));
    });
  });
}
