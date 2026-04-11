# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Internal notes for agentic coding assistants working on this package.

## What this package is

`dart_accuraterip` is a pure-Dart library providing:

1. **AccurateRip v1 / v2 CRC computation** over raw PCM
   (`lib/src/accuraterip_crc.dart`).
2. **Disc-ID computation** from per-track sample counts
   (`lib/src/accuraterip_disc_id.dart`).
3. **Immutable result models** for parsed database responses
   (`lib/src/accuraterip_models.dart`).
4. **Wire-protocol helpers** — URL builder and binary response parser
   (`lib/src/accuraterip_protocol.dart`).
5. **HTTP client convenience wrapper** that takes an injected fetcher
   (`lib/src/io/accuraterip_client.dart`).

The package was extracted from MyMediaScanner to replace duplicated
CRC/client code and give the wider Dart CD-ripping community a
dependable implementation. The companion package is `dart_metaflac`
(pub.dev), which handles FLAC metadata reading and writing.

## Public surface — do not break without a semver bump

All types and functions are re-exported from the single entry point
`package:dart_accuraterip/dart_accuraterip.dart`. The public surface
(preserved deliberately) is:

- `computeArV1(Uint8List, {bool isFirstTrack, bool isLastTrack}) → int`
- `computeArV2(Uint8List, {bool isFirstTrack, bool isLastTrack}) → int`
- `const int accurateRipSkipFrames` (= 2940)
- `class AccurateRipDiscId` with the `const` constructor and the
  `AccurateRipDiscId.fromTrackSampleCounts` factory
- `class AccurateRipDiscResult`, `AccurateRipTrackResult`,
  `AccurateRipEntry` (all immutable, `const` constructors).
  `AccurateRipEntry` has fields `confidence`, `crc`, `frame450Crc`
  and a `matches({required computedV1, required computedV2})`
  helper — **not** `crcV1` / `crcV2`, see Wire-format notes below.
- `Uri buildAccurateRipUrl(AccurateRipDiscId id)`
- `AccurateRipDiscResult? parseAccurateRipResponse(Uint8List bytes)`
- `typedef AccurateRipFetcher = Future<Uint8List> Function(Uri url)`
- `class AccurateRipClient` with `const AccurateRipClient({required AccurateRipFetcher fetch})`
  and `Future<AccurateRipDiscResult?> queryDisc(AccurateRipDiscId id)`
- `Uint8List extractPcmFromWav(Uint8List wavBytes)` — walks a
  RIFF/WAVE byte buffer, returns the `data` chunk payload,
  tolerates extra chunks and truncated data. Throws
  `FormatException` on malformed input. Ported from the private
  `_extractWavData` in `tool/verify_disc.dart` during 0.0.1.
- `int computeArV1FromWav(Uint8List wavBytes, {bool isFirstTrack, bool isLastTrack})`
  and `int computeArV2FromWav(...)` — one-liner wrappers chaining
  `extractPcmFromWav` with the CRC functions.

Renaming or changing the signature of any of these is a breaking
change. Bump the `version:` field in `pubspec.yaml` (currently
`0.0.1`) to `0.1.0` and add an entry to `CHANGELOG.md`.

## Wire-format notes

These are non-obvious and were rediscovered the hard way during
0.0.1 development. Do not strip them from the parser doc comments.

An AccurateRip response body is a concatenation of *chunks*, each
representing one pressing of the disc. Per-chunk layout:

```
trackCount : u8
discId1    : u32 LE
discId2    : u32 LE
cddbDiscId : u32 LE
(confidence : u8 || crc : u32 LE || frame450Crc : u32 LE) × trackCount
```

- **Each entry carries exactly ONE primary CRC.** The server
  stores whatever CRC the submitting ripper sent: older
  submissions stored an AccurateRip v1 CRC, newer submissions
  stored an AccurateRip v2 CRC. The response format provides no
  way to tell which version any given entry was submitted under,
  so the client must try BOTH locally computed CRCs against the
  single `crc` field. `AccurateRipEntry.matches` is the canonical
  helper.
- **There is no per-entry v1/v2 pair.** An earlier iteration of
  this package named the trailing 4-byte field `crcV2` and it was
  wrong. It is `frame450Crc` — a CRC over the first 450 stereo
  frames, used by CUETools for drive-offset verification. It is
  often zero for older pressings. Do not rename it back.
- **Reference implementations consulted:**
  [whipper](https://github.com/whipper-team/whipper) (Python,
  GPL-3.0) and
  [CUETools.NET](https://github.com/gchudov/cuetools.net) (C#,
  `CUETools.AccurateRip/AccurateRip.cs`, `AccTrack` struct at the
  bottom of the file). The golden fixture under `test/fixtures/`
  is redistributed from whipper.

## Design invariants

- **Zero runtime dependencies.** The `pubspec.yaml` runtime section
  must stay empty. `package:http` is a **dev** dependency only,
  used by `example/query_disc.dart`. Consumers plug in their own
  HTTP client via `AccurateRipFetcher`. Do not add `dio`, `http`,
  or any other transport library as a runtime dep without a very
  good reason.
- **CRC has two implementations selected by conditional export.**
  `lib/src/accuraterip_crc_io.dart` is the native 64-bit multiply
  path used on the Dart VM and Flutter native. `lib/src/accuraterip_crc_web.dart`
  is the split 16-bit multiply path used on dart2js / dart2wasm,
  where JavaScript's 53-bit integer precision would otherwise
  silently drop the low bit of the 32×22-bit product. Both files
  export exactly the same public API (`computeArV1`, `computeArV2`,
  `accurateRipSkipFrames`). The conditional export lives in
  `lib/dart_accuraterip.dart` and uses `dart.library.js_interop`
  as the discriminator. The bit-for-bit equivalence of the two
  paths is pinned by `test/accuraterip_crc_differential_test.dart`,
  which runs both on the VM against 350+ random buffers plus the
  hand-pinned overflow fixture. Do not "optimise" the native path
  in a way that changes its output — the differential test is
  load-bearing. `lib/src/wav.dart` uses the same conditional import
  to pick the right CRC implementation for its `FromWav` wrappers.
- **`parseAccurateRipResponse` is tolerant.** A truncated trailing
  chunk should not cause an exception — the parser must return the
  entries it could decode before the short read. There is a test
  for this (`tolerates a truncated trailing chunk without
  crashing`); do not remove it.
- **`AccurateRipClient.queryDisc` returns `null` on any error.**
  Fetcher exceptions, empty bodies, and unparseable responses all
  collapse to `null`. Callers that want to distinguish these cases
  should use `buildAccurateRipUrl` and `parseAccurateRipResponse`
  directly — keep those pure and exported.

## Layout

```
lib/
  dart_accuraterip.dart              # single public export
  src/
    accuraterip_crc.dart             # v1 / v2 CRC
    accuraterip_disc_id.dart         # AccurateRipDiscId
    accuraterip_models.dart          # result models
    accuraterip_protocol.dart        # url builder, response parser
    io/
      accuraterip_client.dart        # AccurateRipClient (fetcher-based)
test/
  accuraterip_crc_test.dart          # synthetic PCM, 7 tests
  accuraterip_disc_id_test.dart      # known-disc sample counts
  accuraterip_protocol_test.dart     # URL shape + hand-built binary fixtures
  accuraterip_client_test.dart       # stubbed fetcher
example/
  compute_crc.dart
  query_disc.dart                    # uses package:http as the fetcher
```

Keep the `src/` layout flat. The only subdirectory is `io/`, which
signals "this is the HTTP-ish layer" even though the code is still
pure Dart. Do not split `accuraterip_models.dart` into three files
unless one of them grows beyond a couple of screens.

## Development commands

```sh
dart pub get
dart analyze                                          # must be clean
dart format --output=none --set-exit-if-changed .      # must be clean
dart test                                             # must pass
dart test test/accuraterip_crc_test.dart              # single test file
dart test test/accuraterip_crc_test.dart -n 'v1 vs v2 divergence' # single test by name
dart run example/compute_crc.dart
dart pub publish --dry-run                            # must report 0 warnings
```

## Testing

- **CRC tests** use synthetic PCM built from `BytesBuilder` /
  `ByteData.setUint32`. They pin the exact arithmetic for small
  sequences, the v1 / v2 divergence at 32-bit overflow, the
  first- and last-track skip, and the empty-input edge case.
- **Disc ID tests** compute known-disc values by hand (see inline
  comments) and assert against the implementation. If you change
  the offset math, re-derive the expected values in a comment —
  do not blindly update the test numbers.
- **Protocol tests** build response bytes by hand via
  `buildChunk()` helpers. There is no real AccurateRip captured
  response in `test/fixtures/` yet; adding one is a **priority
  follow-up** that would let us golden-test the parser against
  production data.
- **Client tests** stub the fetcher with plain closures.

## British English

Documentation and comments use British spelling (`behaviour`,
`licence`, `artefact`). Keep this consistent.

## Licence

GPL-3.0, matching the author's `dart_metaflac` package.

## Follow-ups (not blocking 0.0.1)

- ~~Capture a real AccurateRip response for a well-known disc and
  commit it under `test/fixtures/` as a golden test.~~ **Done** in
  0.0.1 — see `test/fixtures/dBAR-002-0000f21c-00027ef8-05021002.bin`
  (redistributed from whipper) and `test/accuraterip_golden_test.dart`.
- For end-to-end CRC validation against the live database on real
  CDs, use `tool/verify_disc.dart --flac-dir <path>`. It is a
  developer-only script (excluded via `.pubignore`) and shells out
  to the `flac` CLI for PCM decoding plus optionally to
  `accuraterip-checksum` for a third-party cross-check.
- Add a `benchmark/` directory showing CRC throughput on Dart VM.
- Add a minimal `.github/workflows/ci.yaml` running `dart analyze`,
  `dart format --set-exit-if-changed`, and `dart test`.
- ~~Consider a web-safe CRC implementation built on `package:fixnum`
  exposed under a separate entry point.~~ **Done** in 0.0.3, but
  without `package:fixnum` — a pure-Dart split 16-bit multiply in
  `lib/src/accuraterip_crc_web.dart` keeps the zero-runtime-deps
  invariant intact. Selected via conditional export, not a
  separate entry point. See the Design-invariants note above.
