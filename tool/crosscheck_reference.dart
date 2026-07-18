/// Developer-only cross-check of this package's CRC implementation
/// against the third-party `accuraterip-checksum` binary.
///
/// `accuraterip-checksum` (from the whipper project, GPL-3.0) is the
/// de-facto reference implementation. It is not a Dart dependency and
/// is not required to build or test this package — install it
/// separately and run:
///
/// ```sh
/// dart run tool/crosscheck_reference.dart
/// ```
///
/// The script synthesises Red Book WAV files (16-bit stereo,
/// 44 100 Hz) filled with deterministic pseudo-random PCM, then
/// compares our `computeArV1FromWav` / `computeArV2FromWav` against
/// the binary for every first/last track combination. Exits non-zero
/// on the first divergence.
///
/// Author: Paul Snow
/// Since: 0.0.4
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';

/// Build a Red Book CD-DA WAV (16-bit LE stereo, 44 100 Hz) whose
/// data chunk holds [frameCount] stereo frames of pseudo-random PCM.
Uint8List buildWav(int frameCount, int seed) {
  final rng = Random(seed);
  final dataBytes = frameCount * 4;
  final out = BytesBuilder();

  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // PCM fmt chunk size
  u16(1); // audioFormat: PCM
  u16(2); // channels: stereo
  u32(44100); // sampleRate
  u32(44100 * 4); // byteRate
  u16(4); // blockAlign
  u16(16); // bitsPerSample
  ascii('data');
  u32(dataBytes);

  final pcm = Uint8List(dataBytes);
  for (var i = 0; i < dataBytes; i++) {
    pcm[i] = rng.nextInt(256);
  }
  out.add(pcm);

  return out.toBytes();
}

/// Run `accuraterip-checksum` and return its CRC as an int.
int referenceCrc(
  String path,
  int trackNumber,
  int totalTracks, {
  required bool v2,
}) {
  final result = Process.runSync('accuraterip-checksum', [
    v2 ? '--accuraterip-v2' : '--accuraterip-v1',
    path,
    '$trackNumber',
    '$totalTracks',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'accuraterip-checksum failed (${result.exitCode}): ${result.stderr}',
    );
  }
  return int.parse((result.stdout as String).trim(), radix: 16);
}

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('ar_crosscheck_');
  var checks = 0;
  var failures = 0;

  try {
    // Track positions exercising each skip combination. The reference
    // takes (trackNumber, totalTracks) and derives the flags itself.
    const positions = <({int track, int total, String label})>[
      (track: 2, total: 3, label: 'middle track  '),
      (track: 1, total: 3, label: 'first track   '),
      (track: 3, total: 3, label: 'last track    '),
      (track: 1, total: 1, label: 'single-track  '),
    ];

    // Lengths straddling the 2940-frame skip window at both ends.
    const frameCounts = <int>[2939, 2940, 2941, 5879, 5880, 5881, 44100, 97531];

    for (final fc in frameCounts) {
      final wav = buildWav(fc, fc);
      final file = File('${tmp.path}/t_$fc.wav')..writeAsBytesSync(wav);

      for (final p in positions) {
        final isFirst = p.track == 1;
        final isLast = p.track == p.total;

        // Known, deliberate divergence: for a LAST track shorter than
        // the skip window the reference's uint32 bound underflows and
        // it checksums the whole track, while we clamp to an empty
        // window. Unreachable on a real CD (Red Book minimum track is
        // 4 s = 176 400 frames). See the matching test in
        // test/accuraterip_crc_reference_test.dart.
        if (isLast && fc < accurateRipSkipFrames) {
          stdout.writeln(
            'skip  ${p.label}  frames=${fc.toString().padLeft(6)}  '
            'documented divergence (reference uint32 underflow)',
          );
          continue;
        }

        final oursV1 =
            computeArV1FromWav(wav, isFirstTrack: isFirst, isLastTrack: isLast);
        final oursV2 =
            computeArV2FromWav(wav, isFirstTrack: isFirst, isLastTrack: isLast);

        final refV1 = referenceCrc(file.path, p.track, p.total, v2: false);
        final refV2 = referenceCrc(file.path, p.track, p.total, v2: true);

        checks += 2;
        final ok = oursV1 == refV1 && oursV2 == refV2;
        if (!ok) failures++;

        String hex(int v) => v.toRadixString(16).padLeft(8, '0');
        stdout.writeln(
          '${ok ? 'ok  ' : 'FAIL'}  ${p.label}  frames=${fc.toString().padLeft(6)}  '
          'v1 ours=${hex(oursV1)} ref=${hex(refV1)}  '
          'v2 ours=${hex(oursV2)} ref=${hex(refV2)}',
        );
      }
    }
  } finally {
    tmp.deleteSync(recursive: true);
  }

  stdout.writeln('');
  if (failures == 0) {
    stdout.writeln('All $checks checks agree with accuraterip-checksum.');
  } else {
    stderr.writeln('$failures of $checks checks DIVERGED.');
    exitCode = 1;
  }
}
