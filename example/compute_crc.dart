// Compute AccurateRip v1 and v2 CRCs over a synthetic PCM buffer.
//
// In a real ripper you would hand the decoded PCM bytes from one
// track into computeArV1/V2 — see the `dart_accuraterip` README for
// how to decode FLAC to PCM.
//
// Run: dart run example/compute_crc.dart

import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';

void main() {
  // Build a toy PCM buffer: ten stereo frames packed as little-endian
  // uint32 values (left_16 | right_16 << 16).
  final bytes = ByteData(10 * 4);
  for (var i = 0; i < 10; i++) {
    bytes.setUint32(i * 4, (i + 1) * 0x00010001, Endian.little);
  }
  final pcm = bytes.buffer.asUint8List();

  final v1 = computeArV1(pcm);
  final v2 = computeArV2(pcm);

  print('AccurateRip v1 CRC: 0x${v1.toRadixString(16).padLeft(8, '0')}');
  print('AccurateRip v2 CRC: 0x${v2.toRadixString(16).padLeft(8, '0')}');

  // On real ripping workloads you usually pass isFirstTrack/isLastTrack
  // so the 2940-frame lead-in/lead-out region is excluded from the CRC:
  //
  //   final crc = computeArV2(
  //     trackPcm,
  //     isFirstTrack: trackIndex == 0,
  //     isLastTrack: trackIndex == lastTrackIndex,
  //   );
}
