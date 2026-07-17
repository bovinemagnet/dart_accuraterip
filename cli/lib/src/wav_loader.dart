/// Thin CLI-side wrapper around `File(path).readAsBytesSync()` +
/// [extractPcmFromWav] that produces friendlier error messages
/// including the offending file path.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';

/// Load [path] from disk and return its PCM payload.
///
/// Rejects anything that is not Red Book CD-DA (16-bit stereo
/// 44.1 kHz integer PCM) — AccurateRip checksums are undefined for
/// other formats, so refusing loudly beats printing a meaningless
/// CRC.
///
/// Throws a [FormatException] tagged with the file path on any
/// failure — missing file, not a RIFF/WAVE stream, no `data`
/// chunk, or non-Red-Book audio. The tagged message lets the CLI
/// print a single-line error without stack traces leaking into
/// stdout.
Uint8List loadWavPcm(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('file not found: $path');
  }
  final bytes = file.readAsBytesSync();
  try {
    parseWavFormat(bytes).requireRedBookCdAudio();
    return extractPcmFromWav(bytes);
  } on FormatException catch (e) {
    throw FormatException('$path: ${e.message}');
  } on ArgumentError catch (e) {
    // Re-tag the Red Book rejection as the CLI's uniform
    // FormatException error contract (caught → EX_USAGE).
    throw FormatException('$path: ${e.message}');
  }
}
