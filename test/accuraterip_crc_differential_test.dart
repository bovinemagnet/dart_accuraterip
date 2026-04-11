// Differential test: the web split-multiply CRC implementation
// must produce exactly the same output as the native 64-bit
// implementation on every input.
//
// Runs on the VM only (@TestOn('vm')) because the native
// implementation is deliberately broken under dart2js / dart2wasm
// — that's the whole reason the web implementation exists. Both
// implementations compile and execute correctly on the VM, so the
// VM is the right place to compare them.
//
// If this test ever fails, the split-multiply derivation in
// `lib/src/accuraterip_crc_web.dart` has drifted from the
// reference implementation in `lib/src/accuraterip_crc_io.dart`
// and needs to be re-derived. See the comment block in the web
// file for the algebraic decomposition.

@TestOn('vm')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:dart_accuraterip/src/accuraterip_crc_io.dart' as native;
import 'package:dart_accuraterip/src/accuraterip_crc_web.dart' as web;
import 'package:test/test.dart';

/// Build a deterministic-random PCM buffer of [sampleCount] stereo
/// frames. Each frame is a uint32 — the underlying representation
/// the CRC functions consume internally. Values cover the full
/// uint32 range so the test hits every 16-bit half-product branch
/// of the split multiply.
Uint8List randomPcm(Random rng, int sampleCount) {
  final bytes = ByteData(sampleCount * 4);
  for (var i = 0; i < sampleCount; i++) {
    // nextInt(0x100000000) is not valid (exceeds 2^32 - 1 range),
    // so compose from two 16-bit halves.
    final hi = rng.nextInt(0x10000);
    final lo = rng.nextInt(0x10000);
    bytes.setUint32(i * 4, (hi << 16) | lo, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('split-multiply web CRC matches native CRC', () {
    test('v1 and v2 agree on 4-sample hand-pinned fixture', () {
      // Same fixture as the existing accuraterip_crc_test: samples
      // [1, 2, 3, 4], v1 = 30.
      final b = ByteData(16);
      b.setUint32(0, 1, Endian.little);
      b.setUint32(4, 2, Endian.little);
      b.setUint32(8, 3, Endian.little);
      b.setUint32(12, 4, Endian.little);
      final pcm = b.buffer.asUint8List();

      expect(web.computeArV1(pcm), equals(native.computeArV1(pcm)));
      expect(web.computeArV2(pcm), equals(native.computeArV2(pcm)));
      expect(web.computeArV1(pcm), equals(30));
    });

    test('v1 and v2 agree at the 32-bit overflow boundary', () {
      // Two 0xFFFFFFFF samples — exactly the fixture the existing
      // CRC test uses to prove v1/v2 divergence. v1 = 0xFFFFFFFD,
      // v2 = 0xFFFFFFFE.
      final b = ByteData(8);
      b.setUint32(0, 0xFFFFFFFF, Endian.little);
      b.setUint32(4, 0xFFFFFFFF, Endian.little);
      final pcm = b.buffer.asUint8List();

      expect(web.computeArV1(pcm), equals(native.computeArV1(pcm)));
      expect(web.computeArV2(pcm), equals(native.computeArV2(pcm)));
      expect(web.computeArV1(pcm), equals(0xFFFFFFFD));
      expect(web.computeArV2(pcm), equals(0xFFFFFFFE));
    });

    test('v1 and v2 agree on 200 random buffers of varying length', () {
      final rng = Random(0xdeadbeef);
      for (var trial = 0; trial < 200; trial++) {
        // Mix short buffers, medium, and long.
        final sampleCount = switch (trial % 4) {
          0 => rng.nextInt(50) + 1,
          1 => rng.nextInt(5000) + 100,
          2 => rng.nextInt(50000) + 1000,
          _ => rng.nextInt(200000) + 10000,
        };
        final pcm = randomPcm(rng, sampleCount);

        final nv1 = native.computeArV1(pcm);
        final wv1 = web.computeArV1(pcm);
        expect(
          wv1,
          equals(nv1),
          reason: 'v1 mismatch at trial $trial (sampleCount=$sampleCount)'
              '\n  native=0x${nv1.toRadixString(16)}'
              '\n  web   =0x${wv1.toRadixString(16)}',
        );

        final nv2 = native.computeArV2(pcm);
        final wv2 = web.computeArV2(pcm);
        expect(
          wv2,
          equals(nv2),
          reason: 'v2 mismatch at trial $trial (sampleCount=$sampleCount)'
              '\n  native=0x${nv2.toRadixString(16)}'
              '\n  web   =0x${wv2.toRadixString(16)}',
        );
      }
    });

    test('v1 and v2 agree with first-track skip on 50 random buffers', () {
      final rng = Random(0xf00dface);
      for (var trial = 0; trial < 50; trial++) {
        // Must be longer than the 2940-frame skip window so the
        // skip actually takes effect and the post-skip window is
        // non-empty.
        final sampleCount = rng.nextInt(10000) + 3000;
        final pcm = randomPcm(rng, sampleCount);

        expect(
          web.computeArV1(pcm, isFirstTrack: true),
          equals(native.computeArV1(pcm, isFirstTrack: true)),
          reason: 'v1 first-skip mismatch at trial $trial',
        );
        expect(
          web.computeArV2(pcm, isFirstTrack: true),
          equals(native.computeArV2(pcm, isFirstTrack: true)),
          reason: 'v2 first-skip mismatch at trial $trial',
        );
      }
    });

    test('v1 and v2 agree with last-track skip on 50 random buffers', () {
      final rng = Random(0xbaadf00d);
      for (var trial = 0; trial < 50; trial++) {
        final sampleCount = rng.nextInt(10000) + 3000;
        final pcm = randomPcm(rng, sampleCount);

        expect(
          web.computeArV1(pcm, isLastTrack: true),
          equals(native.computeArV1(pcm, isLastTrack: true)),
          reason: 'v1 last-skip mismatch at trial $trial',
        );
        expect(
          web.computeArV2(pcm, isLastTrack: true),
          equals(native.computeArV2(pcm, isLastTrack: true)),
          reason: 'v2 last-skip mismatch at trial $trial',
        );
      }
    });

    test('v1 and v2 agree with both skip flags set on 50 random buffers', () {
      final rng = Random(0xcafecafe);
      for (var trial = 0; trial < 50; trial++) {
        // Must be longer than 2 * 2940 so the middle window is
        // non-empty.
        final sampleCount = rng.nextInt(10000) + 6000;
        final pcm = randomPcm(rng, sampleCount);

        expect(
          web.computeArV1(pcm, isFirstTrack: true, isLastTrack: true),
          equals(
            native.computeArV1(pcm, isFirstTrack: true, isLastTrack: true),
          ),
          reason: 'v1 both-skip mismatch at trial $trial',
        );
        expect(
          web.computeArV2(pcm, isFirstTrack: true, isLastTrack: true),
          equals(
            native.computeArV2(pcm, isFirstTrack: true, isLastTrack: true),
          ),
          reason: 'v2 both-skip mismatch at trial $trial',
        );
      }
    });

    test('both implementations expose the same accurateRipSkipFrames', () {
      expect(web.accurateRipSkipFrames, equals(native.accurateRipSkipFrames));
      expect(web.accurateRipSkipFrames, equals(2940));
    });
  });
}
