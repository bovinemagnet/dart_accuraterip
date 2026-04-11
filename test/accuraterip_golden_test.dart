// Golden tests against a real AccurateRip database response
// captured by the whipper project.
//
// The fixture `dBAR-002-0000f21c-00027ef8-05021002.bin` is
// redistributed from whipper (GPL-3.0). See
// `test/fixtures/README.md` for attribution and the upstream
// commit SHA.
//
// The expected values pinned here come from whipper's own
// `test/test_common_accurip.py` (the `TestAccurateRipResponse`
// class) plus direct decoding of the raw bytes, cross-checked
// against CUETools.NET's entry-layout struct.

import 'dart:io';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

void main() {
  final fixture = File(
    'test/fixtures/dBAR-002-0000f21c-00027ef8-05021002.bin',
  ).readAsBytesSync();

  group('whipper golden fixture (dBAR-002-0000f21c-...)', () {
    test('is exactly 62 bytes — two chunks of 2 tracks each', () {
      // 2 * (13 header + 2 * 9 entry) = 62.
      expect(fixture.lengthInBytes, equals(62));
    });

    test('parseAccurateRipResponse returns two tracks with two entries each',
        () {
      final result = parseAccurateRipResponse(fixture);

      expect(result, isNotNull);
      expect(result!.tracks, hasLength(2));
      expect(result.tracks[0].trackNumber, equals(1));
      expect(result.tracks[1].trackNumber, equals(2));
      expect(result.tracks[0].entries, hasLength(2));
      expect(result.tracks[1].entries, hasLength(2));
    });

    test('track 1 entries match whipper + raw hex values', () {
      final track1 = parseAccurateRipResponse(fixture)!.tracks[0];

      // Pressing 0 (whipper: responses[0].confidences[0] = 12,
      // checksums[0] = 0x284fc705). frame450Crc is the trailing
      // 4-byte field decoded directly from the fixture's hex.
      expect(track1.entries[0].confidence, equals(12));
      expect(track1.entries[0].crc, equals(0x284fc705));
      expect(track1.entries[0].frame450Crc, equals(0x3b97f8a4));

      // Pressing 1 (whipper: responses[1].confidences[0] = 7,
      // checksums[0] = 0xdc77f9ab). Trailing frame450Crc is zero
      // in this pressing — a v1-era submission.
      expect(track1.entries[1].confidence, equals(7));
      expect(track1.entries[1].crc, equals(0xdc77f9ab));
      expect(track1.entries[1].frame450Crc, equals(0));
    });

    test('track 2 entries match whipper + raw hex values', () {
      final track2 = parseAccurateRipResponse(fixture)!.tracks[1];

      // Pressing 0.
      expect(track2.entries[0].confidence, equals(20));
      expect(track2.entries[0].crc, equals(0x9cc1f32e));
      expect(track2.entries[0].frame450Crc, equals(0xdc5500de));

      // Pressing 1.
      expect(track2.entries[1].confidence, equals(7));
      expect(track2.entries[1].crc, equals(0xdd97d2c3));
      expect(track2.entries[1].frame450Crc, equals(0));
    });

    test(
        'AccurateRipEntry.matches accepts either local v1 or local v2 '
        'against the single stored CRC', () {
      final result = parseAccurateRipResponse(fixture)!;
      final track1 = result.tracks[0];

      // Simulate a local rip whose v1 happens to match pressing 0
      // and whose v2 happens to match pressing 1 — exactly the
      // scenario whipper's TestVerifyResult pins.
      const localV1 = 0x284fc705;
      const localV2 = 0xdc77f9ab;

      expect(
        track1.entries[0].matches(computedV1: localV1, computedV2: localV2),
        isTrue,
        reason: 'pressing 0 stores the v1 CRC, local v1 should match',
      );
      expect(
        track1.entries[1].matches(computedV1: localV1, computedV2: localV2),
        isTrue,
        reason: 'pressing 1 stores the v2 CRC, local v2 should match',
      );

      // A rip whose CRCs match nothing in the database should not
      // be mistaken for a match.
      expect(
        track1.entries[0].matches(
          computedV1: 0xDEADBEEF,
          computedV2: 0xCAFEBABE,
        ),
        isFalse,
      );
    });

    test(
        'buildAccurateRipUrl produces the exact filename the fixture '
        'was served from', () {
      // discId1/2/cddb values read from the chunk headers in the
      // fixture (little-endian) and cross-checked against the
      // whipper filename `dBAR-002-0000f21c-00027ef8-05021002.bin`.
      const id = AccurateRipDiscId(
        discId1: 0x0000f21c,
        discId2: 0x00027ef8,
        cddbDiscId: 0x05021002,
        trackCount: 2,
      );

      final uri = buildAccurateRipUrl(id);

      expect(
        uri.path,
        endsWith('/dBAR-002-0000f21c-00027ef8-05021002.bin'),
      );
    });
  });
}
