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
  Deliberately permissive — it never checks the audio format.
- `class WavFormat` (const constructor; `formatCode`, `channels`,
  `sampleRate`, `bitsPerSample`, `isRedBookCdAudio`,
  `requireRedBookCdAudio()`) and
  `WavFormat parseWavFormat(Uint8List wavBytes)` — added in 0.0.5.
  `requireRedBookCdAudio` throws `ArgumentError` (audio format is
  a bad *argument*); `parseWavFormat` throws `FormatException`
  (byte stream is malformed). Keep that split.
- `int computeArV1FromWav(Uint8List wavBytes, {bool isFirstTrack, bool isLastTrack})`
  and `int computeArV2FromWav(...)` — wrappers chaining the Red
  Book check (since 0.0.5), `extractPcmFromWav`, and the CRC
  functions. They throw `ArgumentError` on non-Red-Book input —
  AccurateRip is undefined for anything but 16-bit stereo
  44.1 kHz PCM, and a silently wrong CRC is worse than an error.
  The documented bypass is `computeArV1(extractPcmFromWav(...))`.

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
- **The CRC multiplier is the ABSOLUTE 1-based frame position, and
  the first-track skip is 2939 frames — not 2940.** The reference
  (`compute_checksums()` in `src/accuraterip-checksum.c`) increments
  `MulBy` over every frame and only gates *accumulation* on
  `MulBy >= 2940`. So on track 1 the first counted frame is index
  2939 with multiplier 2940; the multiplier never restarts at the
  window start. The last-track bound is a true count (drop the final
  2940 frames), hence the asymmetry — `accurateRipSkipFrames` is a
  1-based *position* threshold at the head and a *count* at the tail.
  Releases up to 0.0.3 skipped 2940 and restarted the multiplier at
  1, so track 1 of every disc failed to verify. Fixed in 0.0.4 and
  pinned by `test/accuraterip_crc_reference_test.dart`, which
  differentially tests against a line-by-line transliteration of the
  C. That oracle is load-bearing — do not rewrite it to resemble our
  production loop, and do not "simplify" the off-by-one away.
  Cross-checked against the real `accuraterip-checksum` binary (v2.0)
  via `tool/crosscheck_reference.dart`: 60/60 agree.
- **One deliberate divergence from the reference: a LAST track
  shorter than the skip window.** The C `AR_CRCPosCheckTo` is a
  `uint32_t`, so `len - 2940` underflows for a short final track and
  the `MulBy <= To` gate then admits *every* sample — the reference
  returns the full, unskipped checksum. We clamp to an empty window
  and return 0. This is unreachable on a real CD (Red Book minimum
  track length is 4 seconds = 176 400 frames, sixty times the skip
  window), so bug-compatibility buys nothing. Pinned by a test in
  `accuraterip_crc_reference_test.dart` and skipped explicitly by the
  cross-check tool. If you ever make the CRC bug-compatible here,
  change all three together.
- **The lookup URL's three path components are SINGLE hex digits.**
  They are the last, second-to-last, and third-to-last hex digits of
  `discId1`, one character each — `0000f21c` → `c/1/2`. They are not
  growing substrings (`c/1c/21c`), which is what the builder emitted
  up to 0.0.3 and which 404s on the live server. Fixed in 0.0.4;
  pinned by a golden test asserting the exact path of the committed
  fixture, which is confirmed to return HTTP 200 in production.
  Reference: `accuraterip_path()` in `whipper/image/table.py`.
- **The AccurateRip disc IDs use RAW sector offsets — no 150-sector
  lead-in bias.** `discId1` is the plain sum of the track start
  offsets plus the lead-out; `discId2` is the same sum weighted by
  the 1-based track index, with a zero offset (always track 1)
  contributing 1 rather than 0. The 150-sector lead-in bias is a
  FreeDB/CDDB convention and belongs **only** in `cddbDiscId`.
  Releases up to 0.0.3 biased all three IDs by 150, which made every
  lookup URL 404; fixed in 0.0.4 and pinned by the golden disc-ID
  test that reproduces the fixture filename from sample counts. Do
  not reintroduce the bias into `discId1` / `discId2`. Reference:
  `accuraterip_ids()` in `whipper/image/table.py`.
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
  accuraterip_crc_reference_test.dart # differential vs transliterated C (load-bearing)
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
src/docs/                            # Antora docs component -> GitHub Pages
  antora.yml                         # component descriptor + version attributes
  modules/ROOT/                      # library docs (pages/, examples/, nav.adoc)
  modules/cli/                       # command-line tool docs
antora-playbook.yml                  # the only playbook; CI adds flags
package.json                         # Antora toolchain only, not a Dart dep
.github/workflows/
  ci.yml                             # analyse/format/test matrix + docs + publish dry-run
  docs.yml                           # Antora build -> GitHub Pages
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

- **Published to pub.dev** (since cli 0.0.4) with a hosted
  dependency on `dart_accuraterip`. Local development still
  resolves the library from the parent directory via
  `cli/pubspec_overrides.yaml` (ignored by `pub publish`), so
  workspace changes are picked up without publishing.
- **Publish with `tool/publish_cli.sh`, never `cd cli && dart pub
  publish`.** The root `.pubignore` needs a `cli/` pattern to keep
  the cli out of the LIBRARY tarball, but pub applies parent
  ignore files when publishing a sub-directory package (and does
  NOT auto-exclude nested packages — both verified empirically on
  Dart 3.12), so a direct publish fails with "The pubspec is
  hidden". The script exports cli/ to a temp directory outside the
  repo (dropping `pubspec_overrides.yaml`), re-runs get/analyze/
  test there against the real hosted library, and dry-runs by
  default — pass `--publish` for the real thing.
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
  exports a `run<Name>(List<String> argv, IOSink out, {IOSink? err})`
  function that returns the exit code, which is what the tests
  drive. Error messages go to `err` (default `stderr`), so tests
  can assert them.
- It has its own `dart pub get` / `dart analyze` / `dart test`
  cycle — CI runs both packages.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes/PRs to `main`: a
3-OS × {stable, beta} SDK matrix doing format check, analyse
(`--fatal-warnings`) and tests for **both** the root and `cli/`
packages, plus a `dart doc --dry-run` job and a publish-dry-run
job covering both packages (the cli via `tool/publish_cli.sh`,
which validates against the hosted library rather than the
workspace copy).
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
dart run tool/crosscheck_reference.dart   # needs the accuraterip-checksum binary
dart pub publish --dry-run                            # must report 0 warnings
```

Documentation (Antora, published to GitHub Pages):

```sh
npm install                                           # once
npx antora antora-playbook.yml                        # -> build/site/
npx antora --fetch --log-failure-level=error antora-playbook.yml  # what CI runs
```

There is one playbook. It holds the forgiving local defaults
(`fetch: false`, `failure_level: warn`) and CI tightens them with
the two flags above — do not add a second playbook to express that
difference, and do not hard-code `fetch: true`, which cannot be
overridden from the command line.

Do not use `gradle21w antora` here — this is a Dart repository with
no Gradle wrapper. Release numbers referenced by the pages
(`lib-version`, `cli-version`, `min-sdk`) live once in
`src/docs/antora.yml`; bump them there when releasing. A new page
must be added to its module's `nav.adoc` or it will not appear in
the site navigation. Mermaid diagrams are externalised as `.mmd`
files under `modules/<module>/examples/` and rendered through Kroki.

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
- ~~Publish `dart_accuraterip` to pub.dev, then flip the cli's
  `path:` dependency to a version dependency and publish it too.~~
  **Done** — library 0.0.4/0.0.5 published; cli publishable since
  0.0.4 via `tool/publish_cli.sh` (see the CLI sub-package
  section).
- ~~Consider a web-safe CRC implementation built on `package:fixnum`
  exposed under a separate entry point.~~ **Done** in 0.0.3, but
  without `package:fixnum` — a pure-Dart split 16-bit multiply in
  `lib/src/accuraterip_crc_web.dart` keeps the zero-runtime-deps
  invariant intact. Selected via conditional export, not a
  separate entry point. See the Design-invariants note above.
