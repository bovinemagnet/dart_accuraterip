/// Pure-Dart AccurateRip v1/v2 CRC, disc ID computation, and
/// database lookup for CD ripping and verification tools.
///
/// This library has **zero runtime dependencies**. The HTTP client
/// ([AccurateRipClient]) accepts an injected fetcher callback so
/// consumers can bring any HTTP library (`package:http`,
/// `package:dio`, a Flutter `Client`, or a custom stub).
///
/// ## Platform support
///
/// | Surface                                        | VM / Flutter native | Web |
/// | ---------------------------------------------- | :-----------------: | :-: |
/// | [computeArV1] / [computeArV2]                  |         yes         |  no |
/// | [computeArV1FromWav] / [computeArV2FromWav]    |         yes         |  no |
/// | [extractPcmFromWav]                            |         yes         | yes |
/// | [AccurateRipDiscId]                            |         yes         | yes |
/// | [buildAccurateRipUrl]                          |         yes         | yes |
/// | [parseAccurateRipResponse]                     |         yes         | yes |
/// | [AccurateRipClient]                            |         yes         | yes |
///
/// CRC computation (including the `FromWav` wrappers) relies on
/// native 64-bit integer arithmetic that overflows silently on
/// Dart-to-JavaScript targets. The WAV byte-walker
/// [extractPcmFromWav] itself is web-safe — combine it with your
/// own web-safe CRC implementation if you need one.
///
/// ## Quick start
///
/// ```dart
/// import 'dart:typed_data';
/// import 'package:dart_accuraterip/dart_accuraterip.dart';
///
/// Future<void> main() async {
///   // 1. Compute a disc ID from per-track sample counts.
///   final discId = AccurateRipDiscId.fromTrackSampleCounts([
///     13371228, // track 1 — stereo frame count
///     11908704, // track 2
///     // …
///   ]);
///
///   // 2. Query the database (you supply the HTTP fetcher).
///   final client = AccurateRipClient(
///     fetch: (uri) async => /* your HTTP call here */ Uint8List(0),
///   );
///   final result = await client.queryDisc(discId);
///
///   // 3. Verify your ripped PCM against the database entries.
///   //    Compute BOTH v1 and v2 locally — a pressing in the database
///   //    may have been submitted under either AR version, and the
///   //    client cannot tell which without trying both.
///   final Uint8List trackPcmBytes = /* ... */ Uint8List(0);
///   final v1 = computeArV1(trackPcmBytes, isFirstTrack: true);
///   final v2 = computeArV2(trackPcmBytes, isFirstTrack: true);
///   final verified = result?.tracks.first.entries
///       .any((e) => e.matches(computedV1: v1, computedV2: v2)) ?? false;
///   print('verified: $verified');
/// }
/// ```
///
/// If you have a WAV file rather than raw PCM, skip the manual
/// extraction step with [computeArV1FromWav] / [computeArV2FromWav]:
///
/// ```dart
/// import 'dart:io';
/// import 'package:dart_accuraterip/dart_accuraterip.dart';
///
/// final wav = File('track01.wav').readAsBytesSync();
/// final v1 = computeArV1FromWav(wav, isFirstTrack: true);
/// final v2 = computeArV2FromWav(wav, isFirstTrack: true);
/// ```
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

export 'src/accuraterip_crc.dart';
export 'src/accuraterip_disc_id.dart';
export 'src/accuraterip_models.dart';
export 'src/accuraterip_protocol.dart';
export 'src/io/accuraterip_client.dart';
export 'src/wav.dart';
