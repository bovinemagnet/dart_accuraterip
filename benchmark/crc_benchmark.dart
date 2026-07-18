// CRC throughput benchmark for AccurateRip v1 / v2.
//
// Run with:
//
//   dart run benchmark/crc_benchmark.dart
//
// Reports MB/s and samples/s for each CRC variant against a synthetic
// PCM buffer. The buffer is sized to one minute of CD audio (44_100
// stereo frames/s × 60 s × 4 bytes/frame ≈ 10.1 MiB) so the numbers
// approximate single-track throughput on the Dart VM.
//
// This is a VM-only benchmark — the web path uses a separate
// split 16-bit multiply implementation that is exercised by
// `test/accuraterip_crc_differential_test.dart`.
//
// Author: Paul Snow
// Since: 0.0.0

import 'dart:math';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';

const int _sampleRate = 44100;
const int _bytesPerFrame = 4; // 16-bit stereo
const int _seconds = 60;
const int _warmupIterations = 2;
const int _measuredIterations = 5;

void main() {
  final pcm = _buildPcm(_sampleRate * _seconds);
  final megabytes = pcm.lengthInBytes / (1024 * 1024);

  stdout('AccurateRip CRC benchmark');
  stdout('  buffer: ${megabytes.toStringAsFixed(2)} MiB '
      '(${_seconds}s of 44.1 kHz 16-bit stereo PCM)');
  stdout('  warmup: $_warmupIterations   measured: $_measuredIterations');
  stdout('');

  _benchmark('computeArV1', megabytes, () {
    computeArV1(pcm, isFirstTrack: false, isLastTrack: false);
  });
  _benchmark('computeArV2', megabytes, () {
    computeArV2(pcm, isFirstTrack: false, isLastTrack: false);
  });
}

void _benchmark(String label, double megabytes, void Function() run) {
  for (var i = 0; i < _warmupIterations; i++) {
    run();
  }
  final samples = <double>[];
  for (var i = 0; i < _measuredIterations; i++) {
    final sw = Stopwatch()..start();
    run();
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1e6);
  }
  samples.sort();
  final median = samples[samples.length ~/ 2];
  final best = samples.first;
  final mbps = megabytes / best;
  stdout('  $label:  best ${_fmtSeconds(best)}   '
      'median ${_fmtSeconds(median)}   '
      '${mbps.toStringAsFixed(1)} MiB/s');
}

String _fmtSeconds(double s) {
  if (s >= 1) return '${s.toStringAsFixed(3)} s';
  return '${(s * 1000).toStringAsFixed(1)} ms';
}

Uint8List _buildPcm(int stereoFrames) {
  final rng = Random(0xAC0DE);
  final bytes = Uint8List(stereoFrames * _bytesPerFrame);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < stereoFrames; i++) {
    final left = rng.nextInt(1 << 16) - 0x8000;
    final right = rng.nextInt(1 << 16) - 0x8000;
    view.setInt16(i * 4, left, Endian.little);
    view.setInt16(i * 4 + 2, right, Endian.little);
  }
  return bytes;
}

void stdout(String line) {
  // Avoid importing dart:io so the benchmark stays portable to any
  // Dart runtime; `print` is good enough for benchmark output.
  // ignore: avoid_print
  print(line);
}
