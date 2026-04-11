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
  const id = AccurateRipDiscId(
    discId1: 0x0A1B2C3D,
    discId2: 0x11223344,
    cddbDiscId: 0x55667788,
    trackCount: 1,
  );

  group('AccurateRipClient.queryDisc', () {
    test('returns a parsed result when the fetcher yields a valid body',
        () async {
      final body = buildChunk(
        discId1: 0x0A1B2C3D,
        discId2: 0x11223344,
        cddbDiscId: 0x55667788,
        tracks: const [
          (confidence: 7, crc: 0xDEADBEEF, frame450Crc: 0xCAFEBABE),
        ],
      );

      late Uri captured;
      final client = AccurateRipClient(
        fetch: (uri) async {
          captured = uri;
          return body;
        },
      );

      final result = await client.queryDisc(id);

      expect(captured.host, equals('www.accuraterip.com'));
      expect(result, isNotNull);
      expect(result!.tracks, hasLength(1));
      expect(result.tracks.single.entries.single.crc, equals(0xDEADBEEF));
    });

    test('returns null when the fetcher returns an empty body', () async {
      final client = AccurateRipClient(
        fetch: (_) async => Uint8List(0),
      );
      expect(await client.queryDisc(id), isNull);
    });

    test('returns null when the fetcher throws', () async {
      final client = AccurateRipClient(
        fetch: (_) async => throw StateError('404 or network error'),
      );
      expect(await client.queryDisc(id), isNull);
    });

    test('returns null when the body is not a valid AccurateRip stream',
        () async {
      final client = AccurateRipClient(
        fetch: (_) async => Uint8List.fromList([0, 1, 2, 3]),
      );
      expect(await client.queryDisc(id), isNull);
    });
  });
}
