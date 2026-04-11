/// `dart-accuraterip query` — fetch and pretty-print the raw
/// AccurateRip database response for a disc ID. No audio needed.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:io';

import 'package:dart_accuraterip/dart_accuraterip.dart';

import '../args.dart';
import '../io_fetcher.dart';

const String _usage = '''
usage: dart-accuraterip query <discId1-hex> <discId2-hex> <cddbId-hex> <trackCount>

Fetch and pretty-print the AccurateRip database response for a
disc ID. Useful for protocol debugging and for sanity-checking
disc IDs computed elsewhere. Does not require any audio input.

All three disc IDs are parsed as hexadecimal (with or without a
leading "0x"). The trackCount is parsed as decimal.

flags:
  --help     print this message
''';

/// Entry point for the `query` subcommand.
Future<int> runQuery(
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
    final positional = requireExactlyNPositionals(
      args,
      4,
      'query',
      '<discId1-hex> <discId2-hex> <cddbId-hex> <trackCount>',
    );

    final discId1 = _parseHex(positional[0], 'discId1');
    final discId2 = _parseHex(positional[1], 'discId2');
    final cddbId = _parseHex(positional[2], 'cddbDiscId');
    final trackCount = int.tryParse(positional[3]);
    if (trackCount == null || trackCount <= 0) {
      throw FormatException(
        'invalid trackCount: ${positional[3]} (expected a positive integer)',
      );
    }

    final id = AccurateRipDiscId(
      discId1: discId1,
      discId2: discId2,
      cddbDiscId: cddbId,
      trackCount: trackCount,
    );

    out.writeln('Querying: ${buildAccurateRipUrl(id)}');
    out.writeln('');

    final client = AccurateRipClient(fetch: fetcher ?? ioFetcher);
    final result = await client.queryDisc(id);
    if (result == null) {
      out.writeln('No entry in the AccurateRip database for this disc.');
      return 1;
    }

    for (final track in result.tracks) {
      out.writeln(
        'Track ${track.trackNumber.toString().padLeft(2, '0')}: '
        '${track.entries.length} pressing(s)',
      );
      for (final entry in track.entries) {
        out.writeln(
          '  confidence=${entry.confidence.toString().padLeft(3)}  '
          'crc=0x${_hex8(entry.crc)}  '
          'frame450Crc=0x${_hex8(entry.frame450Crc)}',
        );
      }
    }
    return 0;
  } on FormatException catch (e) {
    stderr.writeln('dart-accuraterip query: ${e.message}');
    return 64;
  }
}

int _parseHex(String s, String fieldName) {
  final cleaned = s.toLowerCase().startsWith('0x') ? s.substring(2) : s;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) {
    throw FormatException('invalid $fieldName hex: $s');
  }
  return value;
}

String _hex8(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
