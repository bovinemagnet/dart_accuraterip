# dart_accuraterip

Pure-Dart [AccurateRip][ar] v1/v2 CRC computation, disc-ID math, and
database lookup for CD ripping and verification tools.

[ar]: https://www.accuraterip.com/

**Zero runtime dependencies.** The HTTP client accepts an injected
fetcher callback, so you can bring any HTTP library
(`package:http`, `package:dio`, a Flutter `Client`, or a custom
stub) without forcing a transitive dep on every consumer.

## Features

- **AccurateRip v1 and v2 CRC** over raw PCM (16-bit signed LE,
  stereo interleaved), with optional first/last-track lead-in /
  lead-out skip (the standard 2940-frame exclusion).
- **WAV input helpers** — `extractPcmFromWav`, `computeArV1FromWav`,
  `computeArV2FromWav` walk a RIFF/WAVE byte buffer and run the
  CRC in a single call (tolerant of extra `LIST`/`INFO`/`fact`
  chunks and truncated trailing data).
- **Disc ID computation** from per-track sample counts — produces
  `discId1`, `discId2`, and the legacy `cddbDiscId`.
- **URL builder** for the AccurateRip HTTP database lookup.
- **Binary response parser** for the AccurateRip chunked reply
  format, aggregating multiple pressings per track, with a
  canonical `AccurateRipEntry.matches(computedV1:, computedV2:)`
  verification helper.
- **`AccurateRipClient`** convenience wrapper with an injectable
  fetcher so you can plug in any HTTP layer in two lines.

## Installation

```sh
dart pub add dart_accuraterip
```

Or in `pubspec.yaml`:

```yaml
dependencies:
  dart_accuraterip: ^0.0.1
```

## Platform support

Every surface runs on every Dart platform:

| Surface                                    | Dart VM / Flutter native | Flutter Web / dart2js |
| ------------------------------------------ | :----------------------: | :-------------------: |
| `computeArV1` / `computeArV2`              |            yes           |          yes          |
| `computeArV1FromWav` / `computeArV2FromWav`|            yes           |          yes          |
| `extractPcmFromWav`                        |            yes           |          yes          |
| `AccurateRipDiscId`                        |            yes           |          yes          |
| `buildAccurateRipUrl`                      |            yes           |          yes          |
| `parseAccurateRipResponse`                 |            yes           |          yes          |
| `AccurateRipClient`                        |            yes           |          yes          |

The CRC functions switch implementation at compile time via a
conditional export. On the Dart VM / Flutter native, they use a
single native 64-bit multiply per sample. Under `dart2js` /
`dart2wasm` — where `int` is a JavaScript `double` with only 53
bits of integer precision — they use a split 16-bit multiply
that keeps every intermediate value safely under 2⁵³. Both
implementations produce bit-identical output; a differential
test in `test/accuraterip_crc_differential_test.dart` pins this
against 350+ random buffers plus the 32-bit overflow boundary.
The web path is ~2–3× slower than native, which in practice is
imperceptible because the CRC loop is already memory-bandwidth
bound.

## Quick start

### Compute v1 and v2 CRCs over a track

```dart
import 'package:dart_accuraterip/dart_accuraterip.dart';

final pcm = decodeFlacToPcm('track01.flac'); // your decoder here

final v1 = computeArV1(pcm, isFirstTrack: true);
final v2 = computeArV2(pcm, isFirstTrack: true);
```

### Compute CRCs directly from a WAV file

If your rip is in WAV, you can skip the PCM-extraction step
entirely — the library walks the RIFF chunks for you:

```dart
import 'dart:io';
import 'package:dart_accuraterip/dart_accuraterip.dart';

final wavBytes = File('track01.wav').readAsBytesSync();

final v1 = computeArV1FromWav(wavBytes, isFirstTrack: true);
final v2 = computeArV2FromWav(wavBytes, isFirstTrack: true);
```

`extractPcmFromWav` is also exposed directly for the "I just want
the PCM" case. Both the extractor and the WAV wrappers throw a
`FormatException` if the input is not a valid RIFF/WAVE stream.
The wrappers inherit the same native-`int` platform caveat as the
raw `computeArV1` / `computeArV2` functions (Dart VM / Flutter
native only).

### Compute a disc ID from track sample counts

```dart
final id = AccurateRipDiscId.fromTrackSampleCounts([
  13371228, // track 1 — stereo frame count
  11908704, // track 2
  9847200,  // track 3
]);
```

### Look up the disc in the database (with `package:http`)

```dart
import 'dart:typed_data';
import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:http/http.dart' as http;

final client = AccurateRipClient(
  fetch: (uri) async {
    final response = await http.get(uri);
    if (response.statusCode == 404) return Uint8List(0);
    return response.bodyBytes;
  },
);

final result = await client.queryDisc(id);
for (final track in result?.tracks ?? const []) {
  for (final entry in track.entries) {
    print('track ${track.trackNumber}: '
          'crc=0x${entry.crc.toRadixString(16)} '
          'confidence=${entry.confidence}');
  }
}
```

### Verify a ripped track against the database

Each entry in the AccurateRip database stores **one** primary CRC
per pressing (not a v1 / v2 pair). Some pressings were submitted
by v1-era rippers, others by v2-era rippers, and the client cannot
tell which without trying both. Compute both v1 and v2 locally and
use [`AccurateRipEntry.matches`] to check either against the
entry's single `crc` field:

```dart
final v1 = computeArV1(
  trackPcm,
  isFirstTrack: trackIndex == 0,
  isLastTrack: trackIndex == lastTrackIndex,
);
final v2 = computeArV2(
  trackPcm,
  isFirstTrack: trackIndex == 0,
  isLastTrack: trackIndex == lastTrackIndex,
);

final verified = result!.tracks
    .firstWhere((t) => t.trackNumber == trackIndex + 1)
    .entries
    .any((e) => e.matches(computedV1: v1, computedV2: v2));
```

The secondary `entry.frame450Crc` field (a CRC over the first 450
frames, used by some rippers like CUETools for drive-offset
verification) is exposed for completeness but is not needed for
simple "is my rip bit-accurate?" checks.

### Drop down to the raw protocol helpers

`AccurateRipClient` is optional. If you want full control over the
HTTP layer — caching, retries, header injection, alternate
transports — use the pure helpers directly:

```dart
final url = buildAccurateRipUrl(id);
final bytes = await yourHttpClient.getBytes(url);
final result = parseAccurateRipResponse(bytes);
```

## Examples

Runnable samples live under [`example/`](example/):

- [`compute_crc.dart`](example/compute_crc.dart) — CRC v1/v2 over a
  synthetic PCM buffer.
- [`query_disc.dart`](example/query_disc.dart) — full lookup flow
  using `package:http` as the fetcher.

## Testing

```sh
dart test
```

The unit tests cover the CRC math (including the v1/v2 divergence
at 32-bit overflow, and the first/last-track skip), disc-ID
computation for single- and multi-track discs, URL construction,
hand-built binary response parsing across one and two chunks, and
the client's success / empty / error paths.

## Verification against the real AccurateRip standard

Two complementary layers:

1. **Golden test against a real AccurateRip response.** The test
   suite includes a captured `.bin` response file (`test/fixtures/
   dBAR-002-0000f21c-00027ef8-05021002.bin`, 62 bytes,
   redistributed from [whipper][whipper] under GPL-3.0) and pins
   the decoded CRCs, confidences, and disc-IDs against whipper's
   own test assertions. This proves the parser and URL builder
   agree with an independent, widely-used reference implementation
   on real bytes captured from `accuraterip.com`. The entry-layout
   interpretation (`confidence + crc + frame450Crc`) was
   cross-checked against [CUETools.NET][cuetools]'s parser struct.

2. **Local round-trip self-check tool.** For end-to-end validation
   of the `computeArV1` / `computeArV2` implementations against the
   live database, run `dart run tool/verify_disc.dart --flac-dir
   <path>` against a CD you own. The tool decodes your FLAC files
   via the `flac` CLI, computes the CRCs, queries the database via
   `package:http`, and prints a per-track PASS/FAIL table. If the
   [`accuraterip-checksum`][leo-bogert] binary is on your `$PATH`,
   a third column cross-checks against that independent C
   implementation as well. The tool is not a committed test — it
   exists for developer self-verification against discs we cannot
   redistribute.

[whipper]: https://github.com/whipper-team/whipper
[cuetools]: https://github.com/gchudov/cuetools.net
[leo-bogert]: https://github.com/leo-bogert/accuraterip-checksum

## Protocol references

The AccurateRip database protocol is undocumented; this package's
wire format matches the behaviour observed by several open-source
ripping tools and the HydrogenAudio community's reverse-engineering
efforts. Contributions fixing edge cases against real responses
are welcome.

## Licence

Released under the [GNU General Public License v3.0](LICENSE).
