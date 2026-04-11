# dart_accuraterip examples

Two runnable samples demonstrating the library. Both assume the
package is available via `dart pub get` in the parent directory.

## `compute_crc.dart`

Computes AccurateRip v1 and v2 CRCs over a tiny synthetic PCM
buffer. No network, no file I/O — the shortest possible "does
the library compute a checksum at all?" smoke test.

```sh
dart run example/compute_crc.dart
```

Expected output on any Dart VM / Flutter native target:

```
AccurateRip v1 CRC: 0x01810181
AccurateRip v2 CRC: 0x01810181
```

In a real ripper you would feed the decoded PCM bytes from one
track into `computeArV1` / `computeArV2` — or, if your rip is a
WAV file on disk, the `computeArV1FromWav` /
`computeArV2FromWav` one-liner wrappers added in 0.0.1.

## `query_disc.dart`

Full lookup flow: computes a disc ID from per-track sample
counts, builds the AccurateRip database URL, fetches the
response over HTTP via `package:http`, and prints every
pressing's confidence, stored CRC, and frame450 CRC.

```sh
dart run example/query_disc.dart
```

Note that `package:http` is listed as a **dev dependency only**
in the library's `pubspec.yaml` — this example is the whole
reason it's there. Consumers supply their own HTTP layer by
passing any `Future<Uint8List> Function(Uri)` callback into
`AccurateRipClient`; `package:http` is just one convenient
choice.

The disc IDs in the example file are placeholders — edit them
to reflect a disc you actually own before running, or the
lookup will return "no entry".

## Verifying a rip end-to-end

Neither example covers the final verification step ("does my
rip match the database?"). For that flow see the **Verify a
ripped track against the database** section in the top-level
[`README.md`](../README.md), which shows the
`AccurateRipEntry.matches(computedV1:, computedV2:)` helper,
and the developer-only [`tool/verify_disc.dart`](../tool/verify_disc.dart)
which wires the whole pipeline together for a FLAC rip on disk.
