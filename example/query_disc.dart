// Look up a disc in the AccurateRip database using `package:http`
// as the fetcher backend.
//
// The package itself has **no** HTTP dependency — `AccurateRipClient`
// takes any `Future<Uint8List> Function(Uri)` callback, so you can
// wire in `package:http`, `package:dio`, a mock, or an isolate-safe
// client of your own.
//
// Run: dart run example/query_disc.dart

import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  // Replace these with real per-track sample counts from FLAC
  // STREAMINFO or your CD TOC.
  final trackSampleCounts = [
    13371228, // track 1 — 5:03 @ 44.1 kHz
    11908704, // track 2 — 4:30
    9847200, // track 3 — 3:43
  ];

  final discId = AccurateRipDiscId.fromTrackSampleCounts(trackSampleCounts);

  print('Looking up disc:');
  print('  discId1:    0x${discId.discId1.toRadixString(16).padLeft(8, '0')}');
  print('  discId2:    0x${discId.discId2.toRadixString(16).padLeft(8, '0')}');
  print(
      '  cddbDiscId: 0x${discId.cddbDiscId.toRadixString(16).padLeft(8, '0')}');
  print('  trackCount: ${discId.trackCount}');
  print('  url:        ${buildAccurateRipUrl(discId)}');

  final client = AccurateRipClient(
    fetch: (uri) async {
      final response = await http.get(uri);
      if (response.statusCode == 404) return Uint8List(0);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'HTTP ${response.statusCode}',
          uri,
        );
      }
      return response.bodyBytes;
    },
  );

  final result = await client.queryDisc(discId);
  if (result == null) {
    print('\nNo entry in the AccurateRip database for this disc.');
    return;
  }

  print('\nFound ${result.tracks.length} track(s):');
  for (final track in result.tracks) {
    print('  Track ${track.trackNumber}: ${track.entries.length} pressing(s)');
    for (final entry in track.entries) {
      final crc = entry.crc.toRadixString(16).padLeft(8, '0');
      final f450 = entry.frame450Crc.toRadixString(16).padLeft(8, '0');
      print('    confidence=${entry.confidence}  '
          'crc=0x$crc  frame450Crc=0x$f450');
    }
  }
}
