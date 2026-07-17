# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Internal notes for agentic coding assistants working on this package.

## What this package is

`dart_accuraterip` is a pure-Dart library providing:

1. **AccurateRip v1 / v2 CRC computation** over raw PCM
   (`lib/src/accuraterip_crc_io.dart` on the VM,
   `lib/src/accuraterip_crc_web.dart` on dart2js/dart2wasm —
   see Design invariants).
2. **Disc-ID computation** from per-track sample counts
   (`lib/src/accuraterip_disc_id.dart`).
3. **Immutable result models** for parsed database responses
   (`lib/src/accuraterip_models.dart`).
4. **Wire-protocol helpers** — URL builder and binary response parser
   (`lib/src/accuraterip_protocol.dart`).
5. **HTTP client convenience wrapper** that takes an injected fetcher
   (`lib/src/io/accuraterip_client.dart`).
6. **WAV input helpers** — RIFF walker and `FromWav` CRC wrappers
   (`lib/src/wav.dart`).

The repository also contains `cli/`, a separate unpublished package
(`dart_accuraterip_cli`) providing the `dart-accuraterip` command-line
tool — see the "CLI sub-package" section below.

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
`0.0.4`) and add an entry to `CHANGELOG.md`.

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
- **CRC skip window is asymmetric and the multiplier is absolute.**
  The reference loop (whipper `src/accuraterip-checksum.c`) includes
  1-based sample positions `[2940 .. total − 2940]`: the first track
  skips only the first **2939** samples (5×588 − 1), the last track
  skips the final **2940**, and the multiplier is always the
  sample's absolute position within the track — skipped samples
  still advance it. An earlier iteration of this package restarted
  the multiplier at 1 after the skip and skipped 2940 leading
  samples; it produced wrong first-track CRCs (middle/last tracks
  were coincidentally right because their window starts at
  position 1). Fixed in 0.0.4 and pinned against a real EAC log +
  live database response. Do not "simplify" the `i + 1` multiplier
  back to a window-relative counter.
- **AccurateRip disc IDs use raw LBA offsets — no +150.** Track 1's
  offset is 0; `discId2` counts a zero offset as 1. Only the CDDB
  disc ID applies the 150-sector (2-second) lead-in bias. A
  +150-biased ID looks plausible but 404s on the live database for
  discs it demonstrably holds. Fixed in 0.0.4.
- **The lookup URL shards by the low three NIBBLES of discId1** as
  single hex digits: `/{id1 & 0xF}/{(id1 >> 4) & 0xF}/{(id1 >> 8) & 0xF}/`,
  e.g. `/5/2/7/` for `0x0019e725` — not cumulative substrings like
  `/5/25/725/`. Fixed in 0.0.4; the live-confirmed URL is pinned in
  `test/accuraterip_protocol_test.dart`.
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
  dart_accuraterip.dart              # single public export (conditional CRC export)
  src/
    accuraterip_crc_io.dart          # v1 / v2 CRC — native 64-bit multiply (VM)
    accuraterip_crc_web.dart         # v1 / v2 CRC — split 16-bit multiply (web)
    accuraterip_disc_id.dart         # AccurateRipDiscId
    accuraterip_models.dart          # result models
    accuraterip_protocol.dart        # url builder, response parser
    wav.dart                         # extractPcmFromWav + FromWav wrappers
    io/
      accuraterip_client.dart        # AccurateRipClient (fetcher-based)
test/
  accuraterip_crc_test.dart          # synthetic PCM, pinned arithmetic
  accuraterip_crc_differential_test.dart # io vs web bit-equivalence (load-bearing)
  accuraterip_disc_id_test.dart      # known-disc sample counts
  accuraterip_protocol_test.dart     # URL shape + hand-built binary fixtures
  accuraterip_client_test.dart       # stubbed fetcher
  accuraterip_golden_test.dart       # real whipper response fixture
  accuraterip_wav_test.dart          # RIFF walker edge cases
  fixtures/                          # golden binary response (from whipper)
example/
  compute_crc.dart
  query_disc.dart                    # uses package:http as the fetcher
cli/                                 # separate package, see below
tool/
  verify_disc.dart                   # developer-only, excluded via .pubignore
.github/workflows/
  ci.yml                             # analyse/format/test matrix + docs + publish dry-run
  release.yml                        # compiles CLI binaries on v* tags
```

Keep the `src/` layout flat. The only subdirectory is `io/`, which
signals "this is the HTTP-ish layer" even though the code is still
pure Dart. Do not split `accuraterip_models.dart` into three files
unless one of them grows beyond a couple of screens.

## CLI sub-package (`cli/`)

`cli/` is a second, independent package (`dart_accuraterip_cli`)
providing the `dart-accuraterip` executable with four subcommands:
`crc`, `disc-id`, `verify`, `query`. Key points:

- **Unpublished** (`publish_to: none`) while it depends on the
  library via `path: ../`. When the library ships to pub.dev, swap
  to a version dep and remove the `publish_to` line.
- **Zero dependencies beyond the library** — no `package:args`, no
  `package:http`. Argument parsing is hand-rolled
  (`cli/lib/src/args.dart`) and HTTP uses `dart:io`'s `HttpClient`
  (`cli/lib/src/io_fetcher.dart`). Keep it that way.
- The CLI version constant lives once in `cli/lib/src/version.dart`
  (`cliVersion`), feeding both `--version` and the HTTP User-Agent.
  `cli/test/version_test.dart` pins it to `cli/pubspec.yaml` —
  bump both together or that test fails.
- Exit codes: `64` (EX_USAGE) for usage errors / `FormatException`;
  `verify` exits `1` on any CRC mismatch so it can gate a pipeline.
- Commands live one-per-file under `cli/lib/src/commands/`; each
  exports a `run<Name>(List<String> argv, IOSink out)` function
  that returns the exit code, which is what the tests drive.
- It has its own `dart pub get` / `dart analyze` / `dart test`
  cycle — CI runs both packages.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes/PRs to `main`: a
3-OS × {stable, beta} SDK matrix doing format check, analyse
(`--fatal-warnings`) and tests for **both** the root and `cli/`
packages, plus a `dart doc --dry-run` job and a
`dart pub publish --dry-run` job (root package only — the cli is
`publish_to: none` so it is deliberately excluded from the dry-run).
`.github/workflows/release.yml` compiles the CLI to native binaries
(linux-x64, macos-arm64, windows-x64) on `v*` tags and attaches
them to the GitHub release.

## Development commands

```sh
dart pub get
dart analyze                                          # must be clean
dart format --output=none --set-exit-if-changed .      # must be clean
dart test                                             # must pass
dart test test/accuraterip_crc_test.dart              # single test file
dart test test/accuraterip_crc_test.dart -n 'v1 vs v2 divergence' # single test by name
dart test -p chrome                                   # exercises the web CRC path for real
dart run example/compute_crc.dart
dart pub publish --dry-run                            # must report 0 warnings
```

The `cli/` package has its own cycle (run from `cli/`):

```sh
dart pub get
dart analyze
dart test
dart run bin/dart_accuraterip.dart --help
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
  `buildChunk()` helpers. In addition,
  `test/accuraterip_golden_test.dart` pins the parser against a
  real captured response under `test/fixtures/` (redistributed
  from whipper).
- **Client tests** stub the fetcher with plain closures.
- **CLI tests** (`cli/test/`) drive the `run<Name>()` command
  functions directly with an injected buffer-backed `IOSink`,
  asserting on output text and exit codes — no subprocess forking.

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
- ~~Add a minimal `.github/workflows/ci.yaml` running `dart analyze`,
  `dart format --set-exit-if-changed`, and `dart test`.~~ **Done** —
  see `.github/workflows/ci.yml` and the Continuous-integration
  section above.
- FLAC support in the CLI (currently WAV only — see `cli/README.md`).
- Publish `dart_accuraterip` to pub.dev, then flip the cli's
  `path:` dependency to a version dependency and publish it too.
- ~~Consider a web-safe CRC implementation built on `package:fixnum`
  exposed under a separate entry point.~~ **Done** in 0.0.3, but
  without `package:fixnum` — a pure-Dart split 16-bit multiply in
  `lib/src/accuraterip_crc_web.dart` keeps the zero-runtime-deps
  invariant intact. Selected via conditional export, not a
  separate entry point. See the Design-invariants note above.
