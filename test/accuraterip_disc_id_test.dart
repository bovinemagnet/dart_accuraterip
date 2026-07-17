import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

void main() {
  group('AccurateRipDiscId.fromTrackSampleCounts', () {
    test('single-track disc produces consistent IDs', () {
      // One 3-minute track: 3 * 60 * 44100 = 7938000 stereo frames.
      final id = AccurateRipDiscId.fromTrackSampleCounts([7938000]);

      expect(id.trackCount, equals(1));

      // Track 1 offset = 0; lead-out = 7938000 / 588 = 13500.
      // AccurateRip IDs use raw LBA offsets — no 150-sector bias
      // (that convention belongs to the CDDB ID only).
      // discId1 = 0 + 13500 = 13500.
      expect(id.discId1, equals(13500));

      // discId2 counts a zero offset as 1:
      // discId2 = max(0, 1) * 1 + 13500 * 2 = 1 + 27000 = 27001.
      expect(id.discId2, equals(27001));
    });

    test('multi-track disc produces monotonically different IDs', () {
      // Four 4-minute tracks: 4 * 60 * 44100 = 10584000 frames each.
      final counts = List<int>.filled(4, 10584000);
      final id = AccurateRipDiscId.fromTrackSampleCounts(counts);

      expect(id.trackCount, equals(4));

      // Each track is 10584000 / 588 = 18_000 sectors long.
      // offsets = [0, 18000, 36000, 54000]; lead-out = 72000.
      // discId1 = 0 + 18000 + 36000 + 54000 + 72000 = 180000.
      expect(id.discId1, equals(180000));

      // discId2 = max(0,1)*1 + 18000*2 + 36000*3 + 54000*4 + 72000*5
      //         = 1 + 36000 + 108000 + 216000 + 360000 = 720001.
      expect(id.discId2, equals(720001));
    });

    test('known disc: Faithless — No Roots [UK] (live-database confirmed)', () {
      // Per-track lengths in sectors, taken from the EAC log TOC of
      // a real pressing (track N length = start(N+1) − start(N),
      // lead-out 242503). The expected IDs were confirmed against
      // the live AccurateRip database: the URL built from them
      // returns HTTP 200 with a 5-pressing response, while any
      // +150-biased variant returns 404.
      const sectorLengths = [
        2120, 16821, 12704, 14336, 9774, 12382, 18194, 16629,
        24290, 17025, 20026, 10470, 31356, 20349, 16027, //
      ];
      final id = AccurateRipDiscId.fromTrackSampleCounts(
        [for (final s in sectorLengths) s * 588],
      );

      expect(id.trackCount, equals(15));
      expect(id.discId1, equals(0x0019e725));
      expect(id.discId2, equals(0x0132e444));
      expect(id.cddbDiscId, equals(0xad0ca10f));
    });

    test('custom sample rate is accepted without changing offset math', () {
      // The current algorithm counts sectors as sampleCount / 588
      // regardless of sample rate, so passing a custom rate is a
      // forward-compatibility hook rather than a behavioural change
      // today. This test pins that contract.
      final withDefault = AccurateRipDiscId.fromTrackSampleCounts([7938000]);
      final withCustom = AccurateRipDiscId.fromTrackSampleCounts(
        [7938000],
        sampleRate: 48000,
      );

      expect(withCustom.discId1, equals(withDefault.discId1));
      expect(withCustom.discId2, equals(withDefault.discId2));
      expect(withCustom.trackCount, equals(withDefault.trackCount));
    });

    test('cddbDiscId packs digit sum, total seconds, and track count', () {
      // Single-track 3-minute disc:
      //   offset + 150 = 150 sectors → 150/75 = 2 seconds
      //   digit sum = 2
      //   n = 2 % 255 = 2
      //   total seconds = (13500 + 150)/75 - 2 = 182 - 2 = 180
      //   packed = (2 << 24) | (180 << 8) | 1
      final id = AccurateRipDiscId.fromTrackSampleCounts([7938000]);
      expect(id.cddbDiscId, equals((2 << 24) | (180 << 8) | 1));
    });
  });
}
