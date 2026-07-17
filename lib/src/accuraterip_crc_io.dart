/// AccurateRip CRC v1 and v2 computation over decoded CD audio.
///
/// AccurateRip is a crowd-sourced database of CRCs for each track on
/// commercially-pressed audio CDs. A ripper computes the CRC of its
/// decoded samples and compares against the database to prove the
/// rip is bit-accurate.
///
/// The checksums are computed over raw PCM frames (16-bit signed
/// little-endian, stereo interleaved). Each uint32 frame packs the
/// left and right samples as `left_16bit | (right_16bit << 16)`.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:typed_data';

/// The size in stereo frames of the lead-in/lead-out exclusion
/// window used when computing AccurateRip checksums.
///
/// Equal to `5 * 588` — five CD sectors. The AccurateRip protocol
/// excludes these frames because the disc lead-in/lead-out region is
/// often unreadable or subject to drive-level correction. The
/// reference implementation includes 1-based sample positions
/// `[accurateRipSkipFrames .. total − accurateRipSkipFrames]`, so
/// the first track skips `accurateRipSkipFrames - 1` = 2939 leading
/// samples while the last track skips the final
/// `accurateRipSkipFrames` = 2940 samples — the asymmetry is part
/// of the protocol.
const int accurateRipSkipFrames = 5 * 588;

/// Compute the AccurateRip **v1** CRC of [pcmData].
///
/// [pcmData] is raw PCM bytes: 16-bit signed little-endian, stereo
/// interleaved. Its length must be a multiple of 4 (one stereo frame
/// is 4 bytes). Trailing bytes are ignored.
///
/// When [isFirstTrack] is `true`, the first
/// `accurateRipSkipFrames - 1` (2939) frames are omitted from the
/// checksum. When [isLastTrack] is `true`, the last
/// [accurateRipSkipFrames] (2940) frames are omitted. Both flags
/// may be set for a single-track disc.
///
/// The v1 algorithm multiplies each frame by its 1-based position
/// within the **track** (not the checksum window — skipped frames
/// still advance the multiplier) and sums the low 32 bits of every
/// product. Returns an unsigned 32-bit integer in the range
/// `0..0xFFFFFFFF`.
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
  // The reference implementation includes 1-based positions
  // [skipFrames .. total - skipFrames], so the first-track skip
  // drops only the first (skipFrames - 1) samples while the
  // last-track skip drops the final skipFrames samples. The
  // multiplier is always the absolute 1-based position within the
  // track, NOT restarted at the window start.
  final startIndex = isFirstTrack ? accurateRipSkipFrames - 1 : 0;
  final endIndex = isLastTrack
      ? (totalSamples - accurateRipSkipFrames).clamp(0, totalSamples)
      : totalSamples;

  int crc = 0;

  for (var i = startIndex; i < endIndex; i++) {
    final sample = samples[i];
    crc = (crc + (sample * (i + 1))) & 0xFFFFFFFF;
  }

  return crc;
}

/// Compute the AccurateRip **v2** CRC of [pcmData].
///
/// [pcmData] is raw PCM bytes: 16-bit signed little-endian, stereo
/// interleaved. Its length must be a multiple of 4 (one stereo frame
/// is 4 bytes). Trailing bytes are ignored.
///
/// When [isFirstTrack] is `true`, the first
/// `accurateRipSkipFrames - 1` (2939) frames are omitted from the
/// checksum. When [isLastTrack] is `true`, the last
/// [accurateRipSkipFrames] (2940) frames are omitted.
///
/// The v2 algorithm multiplies each frame by its 1-based position
/// within the **track** (skipped frames still advance the
/// multiplier), then folds the upper 32 bits of the 64-bit product
/// back into the accumulator. This distinguishes rips that would
/// otherwise collide under v1's truncating sum. Returns an
/// unsigned 32-bit integer in the range `0..0xFFFFFFFF`.
///
/// This function uses native 64-bit integer arithmetic and is
/// **not** safe on Dart-to-JavaScript (`dart2js`) or WASM targets
/// where `int` is backed by a JavaScript `double`. Use it only on
/// the Dart VM or Flutter native targets (Android, iOS, macOS,
/// Windows, Linux).
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
  // Same window and absolute-position multiplier as [computeArV1] —
  // see the comment there.
  final startIndex = isFirstTrack ? accurateRipSkipFrames - 1 : 0;
  final endIndex = isLastTrack
      ? (totalSamples - accurateRipSkipFrames).clamp(0, totalSamples)
      : totalSamples;

  int crc = 0;

  for (var i = startIndex; i < endIndex; i++) {
    final sample = samples[i];
    // 64-bit multiply, fold upper 32 bits back into the accumulator.
    final mult = sample * (i + 1);
    crc =
        (crc + (mult & 0xFFFFFFFF) + ((mult >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  }

  return crc;
}
