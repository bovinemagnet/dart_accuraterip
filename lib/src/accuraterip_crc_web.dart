/// Web-safe pure-Dart AccurateRip CRC implementation.
///
/// The native implementation in `accuraterip_crc_io.dart` uses a
/// single 32×32-bit multiply per sample that produces up to
/// ~54-bit products. On the Dart VM that is fine — `int` is a
/// native 64-bit type. Under `dart2js` / `dart2wasm`, `int` is a
/// JavaScript `double` with only 53 bits of integer precision,
/// so the low bit of some products is silently lost and the
/// resulting CRC drifts.
///
/// This file ports the exact same algorithm to a split 16-bit
/// multiply. We decompose both `sample` and `multiplier` into
/// their high and low 16-bit halves, compute four narrow
/// products each of which is at most 32 bits, and reassemble the
/// full 64-bit product as a `(low32, high32)` record. Every
/// intermediate value stays well below 2⁵³, so the arithmetic is
/// exact on every Dart platform.
///
/// ## Derivation
///
///     sample     = sHi * 2¹⁶ + sLo     (sHi, sLo ∈ [0, 2¹⁶))
///     multiplier = mHi * 2¹⁶ + mLo     (mHi, mLo ∈ [0, 2¹⁶))
///
///     product = sample * multiplier
///             = sHi*mHi * 2³² + (sHi*mLo + sLo*mHi) * 2¹⁶ + sLo*mLo
///             = p11 * 2³² + (p10 + p01) * 2¹⁶ + p00
///
/// Each of `p00`, `p01`, `p10`, `p11` is the product of two
/// 16-bit values, so each is bounded by `(2¹⁶ − 1)² < 2³²`. The
/// maximum value of any intermediate sum used below is
/// ~`3 * 2³² ≈ 2³³·⁶`, comfortably under 2⁵³.
///
/// ## Performance
///
/// The split-multiply path is ~2–3× slower than the native path
/// on the Dart VM. The CRC loop is already bounded by memory
/// bandwidth (one `Uint32List` load per frame), so the overhead
/// is dominated by unmeasurably-small arithmetic cost. VM users
/// are routed to the native path via a conditional export in
/// `lib/dart_accuraterip.dart`; they see zero behaviour or
/// performance change.
///
/// Author: Paul Snow
/// Since: 0.0.3
library;

import 'dart:typed_data';

/// The number of stereo frames skipped at the start of the first
/// track and the end of the last track when computing AccurateRip
/// checksums. Kept in lock-step with the native implementation —
/// see `accuraterip_crc_io.dart` for the prose description.
const int accurateRipSkipFrames = 5 * 588;

/// Compute the AccurateRip **v1** CRC of [pcmData] using the
/// web-safe split 16-bit multiply. Produces bit-identical output
/// to the native [accuraterip_crc_io.computeArV1] for every
/// input; see `test/accuraterip_crc_differential_test.dart`.
int computeArV1(
  Uint8List pcmData, {
  bool isFirstTrack = false,
  bool isLastTrack = false,
}) {
  final samples = pcmData.buffer.asUint32List(
    pcmData.offsetInBytes,
    pcmData.lengthInBytes ~/ 4,
  );

  final totalSamples = samples.length;
  final startIndex = isFirstTrack ? accurateRipSkipFrames : 0;
  final endIndex = isLastTrack
      ? (totalSamples - accurateRipSkipFrames).clamp(0, totalSamples)
      : totalSamples;

  int crc = 0;
  int multiplier = 1;

  for (var i = startIndex; i < endIndex; i++) {
    final sample = samples[i];
    crc = (crc + _mulLow32(sample, multiplier)).toUnsigned(32);
    multiplier++;
  }

  return crc;
}

/// Compute the AccurateRip **v2** CRC of [pcmData] using the
/// web-safe split 16-bit multiply.
int computeArV2(
  Uint8List pcmData, {
  bool isFirstTrack = false,
  bool isLastTrack = false,
}) {
  final samples = pcmData.buffer.asUint32List(
    pcmData.offsetInBytes,
    pcmData.lengthInBytes ~/ 4,
  );

  final totalSamples = samples.length;
  final startIndex = isFirstTrack ? accurateRipSkipFrames : 0;
  final endIndex = isLastTrack
      ? (totalSamples - accurateRipSkipFrames).clamp(0, totalSamples)
      : totalSamples;

  int crc = 0;
  int multiplier = 1;

  for (var i = startIndex; i < endIndex; i++) {
    final sample = samples[i];
    // v2 folds the upper 32 bits of the 64-bit product back into
    // the accumulator — equivalent to the native
    // `(mult & 0xFFFFFFFF) + ((mult >> 32) & 0xFFFFFFFF)`.
    final sLo = sample & 0xFFFF;
    final sHi = (sample >>> 16) & 0xFFFF;
    final mLo = multiplier & 0xFFFF;
    final mHi = (multiplier >>> 16) & 0xFFFF;

    final p00 = sLo * mLo;
    final p01 = sLo * mHi;
    final p10 = sHi * mLo;
    final p11 = sHi * mHi;

    // Low 32 bits of the product. Max value of the sum:
    //   p00           < 2³²
    //   (p01&0xFFFF)*2¹⁶  < 2³²
    //   (p10&0xFFFF)*2¹⁶  < 2³²
    // → sum < 3 * 2³² < 2³⁴, safe under 2⁵³.
    final lowSum = p00 + ((p01 & 0xFFFF) << 16) + ((p10 & 0xFFFF) << 16);
    final low32 = lowSum.toUnsigned(32);

    // Carry from the low-sum into bit 32. lowSum < 2³⁴, so the
    // carry fits in 2 bits. Use double division rather than
    // `>>> 32`, because 32-bit JS bitwise ops would silently
    // truncate lowSum to 32 bits before shifting.
    final carry = (lowSum / 0x100000000).floor();

    // High 32 bits of the product:
    //   carry                       ∈ [0, 3]
    //   p01 >>> 16                  < 2¹⁶
    //   p10 >>> 16                  < 2¹⁶
    //   p11                         < 2³²
    final high32 = (carry + (p01 >>> 16) + (p10 >>> 16) + p11).toUnsigned(32);

    crc = (crc + low32 + high32).toUnsigned(32);
    multiplier++;
  }

  return crc;
}

/// Low 32 bits of `sample * multiplier`, computed without any
/// intermediate exceeding ~2³⁴. See the library-level comment for
/// the algebraic derivation.
int _mulLow32(int sample, int multiplier) {
  final sLo = sample & 0xFFFF;
  final sHi = (sample >>> 16) & 0xFFFF;
  final mLo = multiplier & 0xFFFF;
  final mHi = (multiplier >>> 16) & 0xFFFF;

  final p00 = sLo * mLo;
  final p01 = sLo * mHi;
  final p10 = sHi * mLo;
  // p11 contributes only to bits 32+, so we don't need it for
  // the low-32 projection.

  final lowSum = p00 + ((p01 & 0xFFFF) << 16) + ((p10 & 0xFFFF) << 16);
  return lowSum.toUnsigned(32);
}
