/// `dart-accuraterip verify` — end-to-end verification of a rip
/// against the live AccurateRip database.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:io';

import 'package:dart_accuraterip/dart_accuraterip.dart';

import '../args.dart';
import '../io_fetcher.dart';
import '../wav_loader.dart';

const String _usage = '''
usage: dart-accuraterip verify <file1.wav> <file2.wav> ...

Compute AccurateRip v1 and v2 CRCs for each of the given WAV
files (positional order = track order), look up the disc in the
AccurateRip database, and print a per-track PASS/FAIL table.

A track PASSes when either the locally computed v1 or v2 CRC
equals any entry's stored CRC in the database. See
`AccurateRipEntry.matches` for the canonical matching rule.

Exits with status 1 on any mismatch or if no database entry
exists for the disc. Exits with status 64 on usage errors.

flags:
  --help     print this message
''';

/// Entry point for the `verify` subcommand.
///
/// [fetcher] defaults to [ioFetcher], but may be overridden in
/// tests with a stub closure that returns a hand-built response.
Future<int> runVerify(
  List<String> argv,
  IOSink out, {
  AccurateRipFetcher? fetcher,
}) async {
  if (isHelp(argv)) {
    out.writeln(_usage);
    return 0;
  }

  final args = List<String>.from(argv);
  try {
    rejectUnknownFlags(args);
    final paths = requireAtLeastOnePositional(
      args,
      'verify',
      '<file1.wav> <file2.wav> ...',
    );

    // Load every WAV up front so we can compute both sample
    // counts (for disc ID) and CRCs (with correct first/last
    // skip flags).
    final pcms = <List<int>>[];
    for (final path in paths) {
      pcms.add(loadWavPcm(path));
    }

    final sampleCounts = pcms.map((p) => p.length ~/ 4).toList();
    final discId = AccurateRipDiscId.fromTrackSampleCounts(sampleCounts);

    out.writeln('Disc ID:');
    out.writeln('  discId1:    0x${_hex8(discId.discId1)}');
    out.writeln('  discId2:    0x${_hex8(discId.discId2)}');
    out.writeln('  cddbDiscId: 0x${_hex8(discId.cddbDiscId)}');
    out.writeln('  trackCount: ${discId.trackCount}');
    out.writeln('  url:        ${buildAccurateRipUrl(discId)}');
    out.writeln('');

    // Query the database via the injected fetcher (defaults to
    // dart:io HttpClient in production).
    final client = AccurateRipClient(fetch: fetcher ?? ioFetcher);
    final dbResult = await client.queryDisc(discId);
    if (dbResult == null) {
      out.writeln('No entry in the AccurateRip database for this disc.');
      return 1;
    }

    // Compute local v1/v2 per track with proper first/last flags.
    final lastIndex = paths.length - 1;
    final locals = <_LocalCrcs>[];
    for (var i = 0; i < pcms.length; i++) {
      final pcm = pcms[i] as dynamic; // Uint8List under the hood
      locals.add(
        _LocalCrcs(
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
        ),
      );
    }

    // Emit the table.
    out.writeln(
      'track  v1         v2         db match      max-conf  result',
    );
    out.writeln(
      '-----  ---------  ---------  ------------  --------  ------',
    );

    var allPass = true;
    for (var i = 0; i < paths.length; i++) {
      final trackNum = i + 1;
      final local = locals[i];

      final track = dbResult.tracks.firstWhere(
        (t) => t.trackNumber == trackNum,
        orElse: () => const AccurateRipTrackResult(
          trackNumber: 0,
          entries: <AccurateRipEntry>[],
        ),
      );

      // Find the highest-confidence entry that matches either
      // local CRC, then figure out which version actually matched.
      AccurateRipEntry? bestMatch;
      for (final entry in track.entries) {
        if (entry.matches(computedV1: local.v1, computedV2: local.v2)) {
          if (bestMatch == null || entry.confidence > bestMatch.confidence) {
            bestMatch = entry;
          }
        }
      }

      final pass = bestMatch != null;
      if (!pass) allPass = false;

      final matchLabel = bestMatch == null
          ? 'none'
          : (bestMatch.crc == local.v1 ? 'v1 matched' : 'v2 matched');
      final confLabel =
          bestMatch == null ? '--' : bestMatch.confidence.toString();

      out.writeln(
        '${trackNum.toString().padLeft(5)}  '
        '${_hex8(local.v1)}   '
        '${_hex8(local.v2)}   '
        '${matchLabel.padRight(12)}  '
        '${confLabel.padLeft(8)}  '
        '${pass ? 'PASS' : 'FAIL'}',
      );
    }

    out.writeln('');
    out.writeln(
      allPass ? 'All tracks verified.' : 'One or more mismatches.',
    );
    return allPass ? 0 : 1;
  } on FormatException catch (e) {
    stderr.writeln('dart-accuraterip verify: ${e.message}');
    return 64;
  }
}

class _LocalCrcs {
  const _LocalCrcs({required this.v1, required this.v2});
  final int v1;
  final int v2;
}

String _hex8(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
