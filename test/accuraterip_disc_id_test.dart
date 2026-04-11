import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

void main() {
  group('AccurateRipDiscId.fromTrackSampleCounts', () {
    test('single-track disc produces consistent IDs', () {
      // One 3-minute track: 3 * 60 * 44100 = 7938000 stereo frames.
      final id = AccurateRipDiscId.fromTrackSampleCounts([7938000]);

      expect(id.trackCount, equals(1));

      // Track 1 offset = 0; lead-out = 7938000 / 588 = 13500.
      // discId1 = (0 + 150) + (13500 + 150) = 13800.
      expect(id.discId1, equals(13800));

      // discId2 = (0 + 150) * 1 + (13500 + 150) * 2 = 150 + 27300 = 27450.
      expect(id.discId2, equals(27450));
    });

    test('multi-track disc produces monotonically different IDs', () {
      // Four 4-minute tracks: 4 * 60 * 44100 = 10584000 frames each.
      final counts = List<int>.filled(4, 10584000);
      final id = AccurateRipDiscId.fromTrackSampleCounts(counts);

      expect(id.trackCount, equals(4));

      // Each track is 10584000 / 588 = 18_000 sectors long.
      // offsets = [0, 18000, 36000, 54000]; lead-out = 72000.
      // discId1 = (0+150)+(18000+150)+(36000+150)+(54000+150)+(72000+150)
      //         = 150 + 18150 + 36150 + 54150 + 72150 = 180750.
      expect(id.discId1, equals(180750));

      // discId2 = (0+150)*1 + (18000+150)*2 + (36000+150)*3
      //         + (54000+150)*4 + (72000+150)*5
      //         = 150 + 36300 + 108450 + 216600 + 360750 = 722250.
      expect(id.discId2, equals(722250));
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
