// End-to-end AccurateRip self-check tool — FLAC-capable predecessor
// to the WAV-only `cli/` sub-package.
//
// This is NOT part of the published package (see `.pubignore`).
// It is a developer script for verifying that `dart_accuraterip`'s
// CRC math matches:
//
//   (a) the live AccurateRip database for a real CD rip you own,
//       and
//   (b) an independent reference implementation
//       (`accuraterip-checksum`, GPL-3.0, on PATH) when available.
//
// If your rip is in WAV, prefer the `cli/` sub-package:
//
//   dart run cli/bin/dart_accuraterip.dart verify track01.wav …
//
// This tool exists because the CLI does not yet ship FLAC support
// (which requires either an external `flac` CLI or a pure-Dart
// decoder). When FLAC support lands in the CLI, this script can
// be deleted.
//
// Usage:
//
//   dart run tool/verify_disc.dart --flac-dir <path> \
//        [--save-response <file.bin>]
//
// `<path>` should contain a directory of FLAC files for a single
// disc, named in track order (lexical sort is track order — the
// convention every ripper follows). The tool decodes each file via
// the `flac` CLI (which must be on PATH), computes v1/v2 locally,
// queries the AccurateRip database, and prints a PASS/FAIL table.
//
// Exits non-zero on any mismatch so it can be wired into a local
// pre-publish gate if desired.
//
// Author: Paul Snow
// Since: 0.0.1

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  if (args == null) {
    _printUsage(stderr);
    exitCode = 64; // EX_USAGE
    return;
  }

  final flacFiles = _listFlacFiles(args.flacDir);
  if (flacFiles.isEmpty) {
    stderr.writeln('no .flac files found in ${args.flacDir}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  stderr.writeln('Found ${flacFiles.length} FLAC file(s) in ${args.flacDir}');
  for (var i = 0; i < flacFiles.length; i++) {
    stderr.writeln('  ${(i + 1).toString().padLeft(2)}. '
        '${flacFiles[i].uri.pathSegments.last}');
  }

  final hasExternalChecker = await _isOnPath('accuraterip-checksum');
  stderr.writeln(hasExternalChecker
      ? "accuraterip-checksum found on PATH — will cross-check."
      : "accuraterip-checksum NOT on PATH — external column will show '--'.");

  // Decode every track to raw PCM once, up front.
  final pcms = <Uint8List>[];
  final sampleCounts = <int>[];
  for (final file in flacFiles) {
    stderr.writeln('decoding ${file.uri.pathSegments.last}...');
    final pcm = await _decodeFlacToPcm(file.path);
    pcms.add(pcm);
    sampleCounts.add(pcm.lengthInBytes ~/ 4);
  }

  final discId = AccurateRipDiscId.fromTrackSampleCounts(sampleCounts);
  stderr.writeln('\nDisc ID:');
  stderr.writeln('  discId1    = 0x${_hex8(discId.discId1)}');
  stderr.writeln('  discId2    = 0x${_hex8(discId.discId2)}');
  stderr.writeln('  cddbDiscId = 0x${_hex8(discId.cddbDiscId)}');
  stderr.writeln('  trackCount = ${discId.trackCount}');
  stderr.writeln('  url        = ${buildAccurateRipUrl(discId)}');

  // Query the AccurateRip database.
  Uint8List? rawResponse;
  final client = AccurateRipClient(
    fetch: (uri) async {
      final response = await http.get(uri);
      rawResponse = response.bodyBytes;
      if (response.statusCode == 404) return Uint8List(0);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      return response.bodyBytes;
    },
  );

  final dbResult = await client.queryDisc(discId);
  if (dbResult == null) {
    stderr.writeln('\nNo entry in the AccurateRip database for this disc.');
    exitCode = 1;
    return;
  }

  // Persist the raw response if requested.
  if (args.saveResponse != null && rawResponse != null) {
    File(args.saveResponse!).writeAsBytesSync(rawResponse!);
    stderr.writeln('\nWrote raw response to ${args.saveResponse}');
  }

  // Compute our v1 / v2 per track.
  final lastIndex = flacFiles.length - 1;
  final ours = <_Crcs>[];
  for (var i = 0; i < pcms.length; i++) {
    final pcm = pcms[i];
    ours.add(_Crcs(
      v1: computeArV1(
        pcm,
        isFirstTrack: i == 0,
        isLastTrack: i == lastIndex,
      ),
      v2: computeArV2(
        pcm,
        isFirstTrack: i == 0,
        isLastTrack: i == lastIndex,
      ),
    ));
  }

  // Optional: cross-check against accuraterip-checksum.
  final external = <_Crcs?>[];
  if (hasExternalChecker) {
    for (var i = 0; i < flacFiles.length; i++) {
      external.add(await _runExternalChecker(
        flacFiles[i],
        trackNumber: i + 1,
        trackCount: flacFiles.length,
      ));
    }
  } else {
    external.addAll(List<_Crcs?>.filled(flacFiles.length, null));
  }

  // Emit the verification table.
  stdout.writeln('');
  stdout.writeln('track  v1(ours)   v1(db)     v1(ext)    '
      'v2(ours)   v2(db)     v2(ext)    result');
  stdout.writeln('-----  ---------  ---------  ---------  '
      '---------  ---------  ---------  ------');

  var allPass = true;
  for (var i = 0; i < flacFiles.length; i++) {
    final trackNum = i + 1;
    final o = ours[i];
    final dbEntries = dbResult.tracks
        .firstWhere(
          (t) => t.trackNumber == trackNum,
          orElse: () => const AccurateRipTrackResult(
            trackNumber: 0,
            entries: [],
          ),
        )
        .entries;

    final dbV1Hit = dbEntries.any((e) => e.crc == o.v1);
    final dbV2Hit = dbEntries.any((e) => e.crc == o.v2);

    final ext = external[i];
    final extV1Match = ext == null ? null : ext.v1 == o.v1;
    final extV2Match = ext == null ? null : ext.v2 == o.v2;

    final pass = (dbV1Hit || dbV2Hit) &&
        (ext == null || (extV1Match == true && extV2Match == true));
    if (!pass) allPass = false;

    stdout.writeln(
      '${trackNum.toString().padLeft(5)}  '
      '${_hex8(o.v1)}   '
      '${dbV1Hit ? _hex8(o.v1) : "MISS    "}   '
      '${ext == null ? "--      " : _hex8(ext.v1)}   '
      '${_hex8(o.v2)}   '
      '${dbV2Hit ? _hex8(o.v2) : "MISS    "}   '
      '${ext == null ? "--      " : _hex8(ext.v2)}   '
      '${pass ? "PASS" : "FAIL"}',
    );
  }

  stdout.writeln('');
  stdout.writeln(allPass ? 'All tracks verified.' : 'One or more mismatches.');
  exitCode = allPass ? 0 : 1;
}

// --- argument parsing ------------------------------------------------------

class _Args {
  const _Args({required this.flacDir, required this.saveResponse});
  final String flacDir;
  final String? saveResponse;
}

_Args? _parseArgs(List<String> argv) {
  String? flacDir;
  String? saveResponse;
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    switch (arg) {
      case '--flac-dir':
        if (i + 1 >= argv.length) return null;
        flacDir = argv[++i];
      case '--save-response':
        if (i + 1 >= argv.length) return null;
        saveResponse = argv[++i];
      case '-h' || '--help':
        return null;
      default:
        stderr.writeln('unknown argument: $arg');
        return null;
    }
  }
  if (flacDir == null) return null;
  return _Args(flacDir: flacDir, saveResponse: saveResponse);
}

void _printUsage(IOSink sink) {
  sink.writeln('''
verify_disc: end-to-end AccurateRip self-check tool.

usage:
  dart run tool/verify_disc.dart --flac-dir <path> [--save-response <file>]

required:
  --flac-dir <path>       directory of .flac files for one disc,
                          in track order (lexical sort).

optional:
  --save-response <file>  write the raw AccurateRip database response
                          bytes to this path. Useful for harvesting new
                          golden fixtures.

requirements:
  - `flac` on PATH (from the Xiph.Org FLAC tools).
  - network access to http://www.accuraterip.com
  - optionally, `accuraterip-checksum` on PATH for independent
    cross-checking (GPL-3.0, https://github.com/leo-bogert/accuraterip-checksum).
''');
}

// --- file + process helpers ------------------------------------------------

List<File> _listFlacFiles(String dir) {
  final entries = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.flac'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return entries;
}

Future<bool> _isOnPath(String binary) async {
  try {
    final result = await Process.run('which', [binary]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<Uint8List> _decodeFlacToPcm(String flacPath) async {
  final result = await Process.run(
    'flac',
    ['-d', '-c', '-s', flacPath],
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  if (result.exitCode != 0) {
    final stderrStr = result.stderr is List<int>
        ? utf8.decode(result.stderr as List<int>)
        : '${result.stderr}';
    throw StateError('flac decode failed for $flacPath: $stderrStr');
  }
  final wav = Uint8List.fromList(result.stdout as List<int>);
  // Delegates to the library's public helper — previously this file
  // carried its own private copy, but since 0.0.1 extractPcmFromWav
  // is part of package:dart_accuraterip and we use it here to avoid
  // drifting two WAV parsers apart.
  return extractPcmFromWav(wav);
}

Future<_Crcs?> _runExternalChecker(
  File flacFile, {
  required int trackNumber,
  required int trackCount,
}) async {
  // accuraterip-checksum expects a WAV file, not a FLAC. Decode to a
  // temporary WAV first.
  final tmpDir = await Directory.systemTemp.createTemp('darar_ext_');
  final tmpWav = File('${tmpDir.path}/track.wav');
  try {
    final decode = await Process.run(
      'flac',
      ['-d', '-o', tmpWav.path, '-s', '-f', flacFile.path],
    );
    if (decode.exitCode != 0) return null;

    final v1Result = await Process.run(
      'accuraterip-checksum',
      ['--version1', tmpWav.path, '$trackNumber', '$trackCount'],
    );
    final v2Result = await Process.run(
      'accuraterip-checksum',
      ['--version2', tmpWav.path, '$trackNumber', '$trackCount'],
    );
    if (v1Result.exitCode != 0 || v2Result.exitCode != 0) return null;

    final v1 = int.tryParse(
      (v1Result.stdout as String).trim(),
      radix: 16,
    );
    final v2 = int.tryParse(
      (v2Result.stdout as String).trim(),
      radix: 16,
    );
    if (v1 == null || v2 == null) return null;
    return _Crcs(v1: v1, v2: v2);
  } finally {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {/* best-effort cleanup */}
  }
}

class _Crcs {
  const _Crcs({required this.v1, required this.v2});
  final int v1;
  final int v2;
}

String _hex8(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
