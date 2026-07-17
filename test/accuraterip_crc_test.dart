import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

/// Builds PCM bytes from a list of uint32 sample values.
Uint8List buildPcmFromUint32s(List<int> values) {
  final bytes = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    bytes.setUint32(i * 4, values[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('AccurateRip CRC', () {
    test('v1 computes correct CRC for a small known sequence', () {
      // 4 samples [1, 2, 3, 4]:
      // crc = 1*1 + 2*2 + 3*3 + 4*4 = 30
      final pcm = buildPcmFromUint32s([1, 2, 3, 4]);
      expect(computeArV1(pcm), equals(30));
    });

    test('v2 matches v1 for small values (no 32-bit overflow)', () {
      final pcm = buildPcmFromUint32s([1, 2, 3, 4]);
      expect(computeArV2(pcm), equals(30));
    });

    test('v1 and v2 differ for values that overflow 32 bits', () {
      // Two 0xFFFFFFFF samples.
      // v1: crc = 0xFFFFFFFF + (0xFFFFFFFF*2 & 0xFFFFFFFF)
      //        = 0xFFFFFFFF + 0xFFFFFFFE
      //        = 0x1FFFFFFFD & 0xFFFFFFFF = 0xFFFFFFFD
      // v2: folds the high 32 bits back in, yielding 0xFFFFFFFE.
      final pcm = buildPcmFromUint32s([0xFFFFFFFF, 0xFFFFFFFF]);
      final v1 = computeArV1(pcm);
      final v2 = computeArV2(pcm);
      expect(v1, isNot(equals(v2)));
      expect(v1, equals(0xFFFFFFFD));
      expect(v2, equals(0xFFFFFFFE));
    });

    test('first-track skip omits the first 2939 frames (5*588 - 1)', () {
      final values = List.generate(2945, (i) => i + 1);
      final pcm = buildPcmFromUint32s(values);

      final noSkip = computeArV1(pcm);
      final withSkip = computeArV1(pcm, isFirstTrack: true);

      // The reference implementation (whipper accuraterip-checksum.c)
      // includes 1-based positions >= 5*588 = 2940, i.e. it skips only
      // the first 2939 samples, and the multiplier is the absolute
      // position — NOT restarted at the window start. Here sample
      // value k sits at 1-based position k, so each included sample
      // contributes k * k:
      // Σ k² for k in 2940..2945 = 51_949_855.
      expect(withSkip, equals(51949855));
      expect(noSkip, isNot(equals(withSkip)));
    });

    test('last-track skip omits last 2940 frames', () {
      final values = List.generate(2945, (i) => i + 1);
      final pcm = buildPcmFromUint32s(values);

      // Only samples[0..4] = [1..5] contribute:
      // 1 + 4 + 9 + 16 + 25 = 55.
      expect(computeArV1(pcm, isLastTrack: true), equals(55));
    });

    test('empty PCM data returns zero', () {
      final pcm = Uint8List(0);
      expect(computeArV1(pcm), equals(0));
      expect(computeArV2(pcm), equals(0));
    });

    test('single-track disc sets both skip flags and checksums the middle', () {
      // 6000 samples with both flags set. The included window is
      // 1-based positions 2940..3060 (first-track skip drops
      // positions 1..2939; last-track skip drops the final 2940,
      // i.e. positions 3061..6000). The multiplier is the absolute
      // position, and sample value k sits at position k, so each
      // included sample contributes k * k:
      // Σ k² for k in 2940..3060
      //   = 3060·3061·6121/6 − 2939·2940·5879/6
      //   = 9_555_554_310 − 8_466_406_690 = 1_089_147_620.
      final values = List.generate(6000, (i) => i + 1);
      final pcm = buildPcmFromUint32s(values);

      expect(
        computeArV1(pcm, isFirstTrack: true, isLastTrack: true),
        equals(1089147620),
      );
      expect(
        computeArV2(pcm, isFirstTrack: true, isLastTrack: true),
        equals(1089147620),
      );
    });

    test(
        'last-track skip clamps when the track is shorter than the skip '
        'window', () {
      // 100 samples, last-track skip would go negative; clamp to zero
      // so the loop simply never runs and the result is 0 (not a crash).
      final pcm = buildPcmFromUint32s(List.generate(100, (i) => i + 1));
      expect(computeArV1(pcm, isLastTrack: true), equals(0));
      expect(computeArV2(pcm, isLastTrack: true), equals(0));
    });

    test('accurateRipSkipFrames is exposed as a public constant', () {
      expect(accurateRipSkipFrames, equals(2940));
    });
  });
}
