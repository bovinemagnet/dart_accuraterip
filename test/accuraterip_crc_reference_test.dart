// Differential test against a literal transliteration of the
// AccurateRip reference implementation.
//
// Every other CRC expectation in this repo was hand-derived from
// our own understanding of the algorithm, which is exactly how the
// first-track skip came to diverge from the real protocol without a
// single test noticing (issue #3). This file removes that blind spot
// by transliterating whipper's `compute_checksums()` from
// `src/accuraterip-checksum.c` (GPL-3.0) directly into Dart and
// asserting our implementation agrees with it.
//
// The oracle below is deliberately a dumb, slow, line-by-line port of
// the C — it is NOT to be "tidied up" to look like our production
// loop. Its whole value is that it was written from the reference,
// independently of `accuraterip_crc_io.dart`.
//
// VM-only: the oracle relies on native 64-bit integer arithmetic, the
// same reason `accuraterip_crc_io.dart` exists.

@TestOn('vm')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

/// Literal port of whipper's `compute_checksums()`:
///
/// ```c
/// uint32_t AR_CRCPosCheckFrom = 0;
/// uint32_t AR_CRCPosCheckTo = Datauint32_tSize;
/// uint32_t MulBy = 1;
///
/// if (track_number == 1)
///     AR_CRCPosCheckFrom += ((SectorBytes * 5) / sizeof(uint32_t));
/// if (track_number == total_tracks)
///     AR_CRCPosCheckTo -= ((SectorBytes * 5) / sizeof(uint32_t));
///
/// for (i = 0; i < Datauint32_tSize; i++) {
///     if (MulBy >= AR_CRCPosCheckFrom && MulBy <= AR_CRCPosCheckTo) {
///         uint64_t product = (uint64_t)audio_data[i] * (uint64_t)MulBy;
///         csum_hi += (uint32_t)(product >> 32);
///         csum_lo += (uint32_t)(product);
///     }
///     MulBy++;
/// }
/// *v1 = csum_lo;
/// *v2 = csum_lo + csum_hi;
/// ```
///
/// Note `MulBy` is incremented unconditionally, so it is always the
/// absolute 1-based sample position — it does **not** restart at 1
/// after the skipped lead-in samples. With `From = 2940` the first
/// *included* sample is the one at 0-based index 2939, multiplied by
/// 2940. That is 2939 samples skipped, not 2940.
///
/// `AR_CRCPosCheckTo` is a `uint32_t`, so on a **last track shorter
/// than the skip window** the subtraction underflows and wraps to a
/// huge value, which makes the `MulBy <= To` gate admit every sample
/// — the reference then returns the full, unskipped checksum. That is
/// emulated faithfully below with a 32-bit wrap. We deliberately do
/// **not** copy that behaviour in production (we clamp to an empty
/// window instead); the divergence is unreachable on a real CD, where
/// the Red Book minimum track length is 4 seconds — 176 400 frames,
/// sixty times the skip window. See the dedicated test at the bottom.
({int v1, int v2}) referenceCrcs(
  Uint32List samples, {
  required bool isFirstTrack,
  required bool isLastTrack,
}) {
  var csumHi = 0;
  var csumLo = 0;
  var posCheckFrom = 0;
  var posCheckTo = samples.length;
  var mulBy = 1;

  if (isFirstTrack) {
    posCheckFrom += accurateRipSkipFrames;
  }
  if (isLastTrack) {
    // `& 0xFFFFFFFF` reproduces the C uint32_t underflow described above.
    posCheckTo = (posCheckTo - accurateRipSkipFrames) & 0xFFFFFFFF;
  }

  for (var i = 0; i < samples.length; i++) {
    if (mulBy >= posCheckFrom && mulBy <= posCheckTo) {
      final product = samples[i] * mulBy;
      csumHi = (csumHi + ((product >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      csumLo = (csumLo + (product & 0xFFFFFFFF)) & 0xFFFFFFFF;
    }
    mulBy++;
  }

  return (v1: csumLo, v2: (csumLo + csumHi) & 0xFFFFFFFF);
}

Uint8List pcmFrom(Uint32List samples) =>
    samples.buffer.asUint8List(0, samples.lengthInBytes);

void main() {
  group('CRC agrees with the reference implementation', () {
    // Fixed seed: a failure must be reproducible, not a one-off.
    final rng = Random(20260714);

    Uint32List randomSamples(int count) {
      final s = Uint32List(count);
      for (var i = 0; i < count; i++) {
        // Full 32-bit range, so v1/v2 diverge via 32-bit overflow.
        s[i] = rng.nextInt(0x100000000);
      }
      return s;
    }

    for (final flags in const [
      (first: false, last: false, label: 'middle track'),
      (first: true, last: false, label: 'first track'),
      (first: false, last: true, label: 'last track'),
      (first: true, last: true, label: 'single-track disc'),
    ]) {
      test('matches the reference on random buffers — ${flags.label}', () {
        // Lengths straddling the 2940-frame skip window: shorter than
        // the skip, exactly the skip, one frame either side, and
        // comfortably longer.
        for (final count in const [
          0,
          1,
          100,
          2939,
          2940,
          2941,
          5879,
          5880,
          5881,
          9000,
        ]) {
          // A last track shorter than the skip window is where the C
          // reference underflows its uint32 bound and checksums the
          // whole track. We clamp instead — a deliberate divergence on
          // input that cannot occur on a real CD, pinned separately
          // below rather than smuggled through this loop.
          if (flags.last && count < accurateRipSkipFrames) continue;

          final samples = randomSamples(count);
          final pcm = pcmFrom(samples);

          final expected = referenceCrcs(
            samples,
            isFirstTrack: flags.first,
            isLastTrack: flags.last,
          );

          expect(
            computeArV1(pcm,
                isFirstTrack: flags.first, isLastTrack: flags.last),
            equals(expected.v1),
            reason: 'v1 diverged at length $count (${flags.label})',
          );
          expect(
            computeArV2(pcm,
                isFirstTrack: flags.first, isLastTrack: flags.last),
            equals(expected.v2),
            reason: 'v2 diverged at length $count (${flags.label})',
          );
        }
      });
    }

    test('the first included sample of track 1 is index 2939, times 2940', () {
      // The regression that issue #3 fixed, pinned as a standalone
      // fact rather than an emergent property of a random buffer.
      //
      // Buffer of 2941 samples, all zero except index 2939 (value 1)
      // and index 2940 (value 1).
      //   - Under the reference: index 2939 contributes 1 * 2940 and
      //     index 2940 contributes 1 * 2941 → 5881.
      //   - Under the pre-fix code (skip 2940, multiplier restarts at
      //     1): index 2939 was dropped entirely and index 2940
      //     contributed 1 * 1 → 1.
      final samples = Uint32List(2941);
      samples[2939] = 1;
      samples[2940] = 1;

      expect(
        computeArV1(pcmFrom(samples), isFirstTrack: true),
        equals(2940 + 2941),
      );
    });

    test(
        'deliberately diverges from the reference when a LAST track is '
        'shorter than the skip window', () {
      // Confirmed against the real `accuraterip-checksum` binary
      // (v2.0): for a last track of 2939 frames it returns the full,
      // unskipped checksum — byte-identical to the middle-track value.
      // That is not intentional protocol design, it is C unsigned
      // underflow: `AR_CRCPosCheckTo` is a uint32_t, 2939 - 2940 wraps
      // to 0xFFFFFFFF, and the `MulBy <= To` gate then admits
      // everything.
      //
      // We clamp to an empty window and return 0 instead. The input is
      // unreachable on a real CD (Red Book minimum track length is 4
      // seconds = 176 400 frames), so bug-compatibility buys nothing
      // and a silently-full checksum on a degenerate buffer is the
      // more surprising answer. Pinned here so the choice is visible
      // and deliberate rather than an accident.
      final samples = Uint32List(accurateRipSkipFrames - 1);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = i + 1;
      }
      final pcm = pcmFrom(samples);

      final unskipped = computeArV1(pcm);
      final reference = referenceCrcs(
        samples,
        isFirstTrack: false,
        isLastTrack: true,
      );

      // The reference underflows and checksums the whole track...
      expect(reference.v1, equals(unskipped));
      // ...whereas we return an empty window.
      expect(computeArV1(pcm, isLastTrack: true), equals(0));
      expect(computeArV2(pcm, isLastTrack: true), equals(0));
    });
  });
}
