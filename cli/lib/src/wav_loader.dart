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
/// Throws a [FormatException] tagged with the file path on any
/// failure — missing file, not a RIFF/WAVE stream, or no `data`
/// chunk. The tagged message lets the CLI print a single-line
/// error without stack traces leaking into stdout.
Uint8List loadWavPcm(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('file not found: $path');
  }
  final bytes = file.readAsBytesSync();
  try {
    return extractPcmFromWav(bytes);
  } on FormatException catch (e) {
    throw FormatException('$path: ${e.message}');
  }
}
