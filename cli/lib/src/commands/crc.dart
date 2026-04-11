/// `dart-accuraterip crc` — compute AccurateRip v1 and v2 CRCs
/// for a single WAV file.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:io';

import 'package:dart_accuraterip/dart_accuraterip.dart';

import '../args.dart';
import '../wav_loader.dart';

const String _usage = '''
usage: dart-accuraterip crc [--first] [--last] <file.wav>

Compute AccurateRip v1 and v2 CRCs over a single WAV file's PCM
payload and print both as 8-character lowercase hex.

flags:
  --first    skip the first 2940 stereo frames (first track on the disc)
  --last     skip the last 2940 stereo frames (last track on the disc)
  --help     print this message

Both skip flags may be set together on a single-track disc.
''';

/// Entry point for the `crc` subcommand.
///
/// Returns the intended exit code — the caller in `bin/` is
/// responsible for assigning it to `exitCode`.
Future<int> runCrc(List<String> argv, IOSink out) async {
  if (isHelp(argv)) {
    out.writeln(_usage);
    return 0;
  }

  final args = List<String>.from(argv);
  final isFirst = parseBooleanFlag(args, '--first');
  final isLast = parseBooleanFlag(args, '--last');

  try {
    rejectUnknownFlags(args);
    final path =
        requirePositional(args, 'crc', '[--first] [--last] <file.wav>');
    final pcm = loadWavPcm(path);
    final v1 = computeArV1(pcm, isFirstTrack: isFirst, isLastTrack: isLast);
    final v2 = computeArV2(pcm, isFirstTrack: isFirst, isLastTrack: isLast);
    out.writeln('v1: ${_hex8(v1)}');
    out.writeln('v2: ${_hex8(v2)}');
    return 0;
  } on FormatException catch (e) {
    stderr.writeln('dart-accuraterip crc: ${e.message}');
    return 64;
  }
}

String _hex8(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
