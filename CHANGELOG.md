# Changelog

## 0.0.4

Three correctness fixes, all discovered by end-to-end verification
of a real EAC rip against the live AccurateRip database and pinned
by new regression tests. **If you used 0.0.3 or earlier for
database lookups or first-track CRCs, upgrade — those results were
wrong.**

- **First-track CRC skip fixed.** `computeArV1` / `computeArV2`
  (and the `FromWav` wrappers) previously restarted the multiplier
  at 1 after the first-track skip and skipped 2940 samples. The
  reference implementation (whipper's `accuraterip-checksum.c`)
  includes 1-based positions `>= 2940` — i.e. it skips only the
  first 2939 samples — and the multiplier is always the sample's
  absolute position within the track. Middle- and last-track CRCs
  were unaffected (the window starts at position 1, making the two
  schemes identical there); first-track CRCs were wrong. Now
  verified byte-for-byte against an EAC rip log and a live
  database response (confidence 19).
- **AccurateRip disc IDs fixed.**
  `AccurateRipDiscId.fromTrackSampleCounts` biased every track
  offset by +150 sectors when computing `discId1` / `discId2`. The
  canonical algorithm uses raw LBA offsets (track 1 = 0; a zero
  offset counts as 1 in `discId2`). The 150-sector lead-in bias
  applies only to the CDDB disc ID, which was — and remains —
  correct.
- **Lookup URL path fixed.** `buildAccurateRipUrl` built the three
  directory levels as cumulative substrings of `discId1`
  (`/5/25/725/`); the database actually shards by the low three
  nibbles as single hex digits (`/5/2/7/`). The old URLs returned
  404 for every disc.
- New regression tests pin a live-confirmed disc
  (Faithless — *No Roots* [UK]): disc IDs, lookup URL, and the
  updated hand-derived CRC windows. The io/web differential test
  continues to pin bit-identical output across both CRC
  implementations.

## 0.0.3

- **Web-safe CRC implementation.** `computeArV1`, `computeArV2`,
  and their `FromWav` wrappers now produce correct results under
  `dart2js` and `dart2wasm`. Previously the inner loop's 32×22-bit
  multiply could produce a product up to ~54 bits wide, which is
  silently truncated by JavaScript's 53-bit integer precision and
  caused wrong CRCs on the web.
- The fix is a pure-Dart split 16-bit multiply. `sample` and
  `multiplier` are each decomposed into two 16-bit halves; four
  narrow multiplies each yield at most a 32-bit product; the full
  64-bit product is reassembled as a `(low32, high32)` record
  where every intermediate value stays safely under 2⁵³.
- Selected at compile time via a conditional export in
  `lib/dart_accuraterip.dart`:
  ```dart
  export 'src/accuraterip_crc_io.dart'
      if (dart.library.js_interop) 'src/accuraterip_crc_web.dart';
  ```
  Dart VM / Flutter native users see zero behaviour or performance
  change — they continue to get the single-multiply native path.
  Web users transparently get the split-multiply path, which is
  ~2–3× slower in pure arithmetic but imperceptible overall because
  the CRC loop is memory-bandwidth bound.
- New differential test in
  `test/accuraterip_crc_differential_test.dart` runs both
  implementations side-by-side on the VM and asserts bit-identical
  output across 200 random PCM buffers (varying length from 1 to
  200,000 samples), the 32-bit overflow boundary fixture, and all
  first/last-track skip permutations over another 150 random
  buffers.
- The full `accuraterip_crc_test.dart` and `accuraterip_wav_test.dart`
  suites now run and pass under `dart test -p chrome`, exercising
  the conditional export for real.
- README and library-level dartdoc platform-support tables
  updated — every surface now reads `yes / yes`. The native-only
  caveat paragraph is replaced by a short explanation of the
  two-implementation strategy.
- No public API changes. 0.0.2 consumers can upgrade freely;
  anyone who was previously working around the web limitation can
  drop their workaround.

## 0.0.2

- Fix pub.dev score deductions flagged against 0.0.1:
  - `README.md` — change the AccurateRip marketing link from
    `http://www.accuraterip.com/` to `https://www.accuraterip.com/`
    so pub.dev's insecure-link check is satisfied. The runtime
    `buildAccurateRipUrl` output is unchanged because the
    AccurateRip database API itself remains HTTP-only.
  - Add `example/README.md` — a landing page describing the two
    existing runnable samples (`compute_crc.dart` and
    `query_disc.dart`). pub.dev's example detector only
    recognises a handful of canonical filenames; adding an
    `example/README.md` satisfies the check without renaming
    the existing files.
- No library API changes; 0.0.1 consumers can upgrade freely.

## 0.0.1

- Initial release.
- AccurateRip v1 and v2 CRC computation over 16-bit signed
  little-endian stereo PCM, with optional first/last-track skip of
  the 2940-sample CD lead-in/lead-out region.
- `AccurateRipDiscId.fromTrackSampleCounts` computes the
  AccurateRip disc ID fields (`discId1`, `discId2`, `cddbDiscId`,
  `trackCount`) from per-track sample counts.
- Immutable result models: `AccurateRipDiscResult`,
  `AccurateRipTrackResult`, `AccurateRipEntry`. Each
  `AccurateRipEntry` exposes the single server-stored `crc` (which
  may be an AR v1 or AR v2 value depending on the submitting
  ripper's era) and a secondary `frame450Crc` (a CRC over the
  first 450 frames used by CUETools for drive-offset detection).
  A convenience `matches(computedV1:, computedV2:)` method
  performs the canonical verification: a pressing matches if
  either locally computed CRC equals the entry's `crc`.
- `buildAccurateRipUrl` constructs the three-component hex path
  URL for the AccurateRip HTTP database lookup.
- `parseAccurateRipResponse` decodes the AccurateRip binary
  response format (chunked 13-byte headers + 9-byte per-track
  entries, little-endian) into the result models. The entry-layout
  interpretation was cross-checked against the whipper and
  CUETools.NET reference implementations; the golden test suite
  pins a real 62-byte response redistributed from whipper.
- `AccurateRipClient` convenience wrapper with an injectable
  fetcher callback, so the package carries **zero runtime
  dependencies** and works with any HTTP client (`package:http`,
  `package:dio`, a Flutter `Client`, or a custom stub).
- WAV input helpers: `extractPcmFromWav` walks a RIFF/WAVE byte
  buffer (tolerant of extra `LIST`/`INFO`/`fact` chunks and
  truncated trailing data) and returns the raw PCM payload, plus
  `computeArV1FromWav` and `computeArV2FromWav` one-liner wrappers
  that chain the extractor with the CRC functions. Throws
  `FormatException` on malformed input.
