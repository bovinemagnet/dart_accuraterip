/// `dart-accuraterip disc-id` — compute an AccurateRip disc ID
/// from a list of WAV files given in track order.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:io';

import 'package:dart_accuraterip/dart_accuraterip.dart';

import '../args.dart';
import '../wav_loader.dart';

const String _usage = '''
usage: dart-accuraterip disc-id <file1.wav> <file2.wav> ...

Compute an AccurateRip disc ID (discId1, discId2, cddbDiscId,
trackCount) from a list of WAV files representing the tracks of
a single disc. Positional order is track order — if your rip is
named lexically (track01.wav, track02.wav, ...) the shell's glob
expansion is enough.

flags:
  --help     print this message
''';

/// Entry point for the `disc-id` subcommand.
Future<int> runDiscId(List<String> argv, IOSink out) async {
  if (isHelp(argv)) {
    out.writeln(_usage);
    return 0;
  }

  final args = List<String>.from(argv);
  try {
    rejectUnknownFlags(args);
    final paths = requireAtLeastOnePositional(
      args,
      'disc-id',
      '<file1.wav> <file2.wav> ...',
    );

    final sampleCounts = <int>[];
    for (final path in paths) {
      final pcm = loadWavPcm(path);
      // 4 bytes per stereo frame (16-bit LE × 2 channels).
      sampleCounts.add(pcm.lengthInBytes ~/ 4);
    }

    final id = AccurateRipDiscId.fromTrackSampleCounts(sampleCounts);
    out.writeln('discId1:    0x${_hex8(id.discId1)}');
    out.writeln('discId2:    0x${_hex8(id.discId2)}');
    out.writeln('cddbDiscId: 0x${_hex8(id.cddbDiscId)}');
    out.writeln('trackCount: ${id.trackCount}');
    out.writeln('url:        ${buildAccurateRipUrl(id)}');
    return 0;
  } on FormatException catch (e) {
    stderr.writeln('dart-accuraterip disc-id: ${e.message}');
    return 64;
  }
}

String _hex8(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
