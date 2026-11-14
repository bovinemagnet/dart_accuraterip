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
// Each CRC is measured twice: on a 4-byte-aligned buffer (the
// zero-copy path) and on a view starting 2 bytes into its buffer,
// which is what `extractPcmFromWav` returns for a WAV whose chunks
// before `data` leave the payload misaligned (a typical ffmpeg
// `LIST`/`INFO` chunk). Misaligned input is copied before
// checksumming, so the gap between the two rows is the cost of that
// copy.
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

  // The same bytes, viewed 2 bytes into a larger buffer.
  final backing = Uint8List(pcm.length + 2)..setRange(2, pcm.length + 2, pcm);
  final misaligned = Uint8List.sublistView(backing, 2);

  _benchmark('computeArV1 (aligned)   ', megabytes, () {
    _sink += computeArV1(pcm, isFirstTrack: false, isLastTrack: false);
  });
  _benchmark('computeArV1 (misaligned)', megabytes, () {
    _sink += computeArV1(misaligned, isFirstTrack: false, isLastTrack: false);
  });
  _benchmark('computeArV2 (aligned)   ', megabytes, () {
    _sink += computeArV2(pcm, isFirstTrack: false, isLastTrack: false);
  });
  _benchmark('computeArV2 (misaligned)', megabytes, () {
    _sink += computeArV2(misaligned, isFirstTrack: false, isLastTrack: false);
  });
  stdout('');
  stdout('  (result sink: 0x${_sink.toRadixString(16)})');
}

/// Every result is folded in here and printed at the end, so the VM
/// cannot discard a CRC call whose result would otherwise be unused.
int _sink = 0;

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
