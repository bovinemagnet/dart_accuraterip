# Changelog

## 0.0.4

- **First pub.dev release.** The dependency on `dart_accuraterip`
  is now a version constraint (`^0.0.5`) instead of a local path,
  so `dart pub global activate dart_accuraterip_cli` works as the
  README describes. Local development still resolves the library
  from the parent directory via `pubspec_overrides.yaml`.
- All four subcommands accept an injectable `err` sink (defaulting
  to `stderr`), so failure messages are assertable in tests rather
  than escaping to the process's real stderr.
- `verify` uses a properly typed `List<Uint8List>` for loaded PCM
  buffers, removing an `as dynamic` cast.

## 0.0.3

- `crc`, `disc-id`, and `verify` now reject WAV input that is not
  Red Book CD-DA (16-bit stereo 44.1 kHz integer PCM) with a
  single-line error and exit code 64, instead of silently printing
  a physically meaningless CRC. Uses the library's new
  `parseWavFormat` / `WavFormat.requireRedBookCdAudio` surface
  (dart_accuraterip 0.0.5).

## 0.0.2

- Rebuilt against `dart_accuraterip` 0.0.4, which fixes three
  correctness bugs that made earlier CLI results wrong: first-track
  CRC skip semantics, AccurateRip disc-ID computation (+150 bias
  removed), and the database lookup URL path (nibble directories).
  `verify` and `query` previously reported "No entry in the
  AccurateRip database" for discs the database holds, and `crc`
  printed wrong values for first tracks (`--first`).
- The version constant now lives in `lib/src/version.dart` as the
  single source of truth for both `--version` and the HTTP
  User-Agent, with a test pinning it to `pubspec.yaml` so the pair
  can no longer drift (the 0.0.1 → 0.0.2 bump had already missed
  the hard-coded User-Agent).
- No CLI-level interface changes.

## 0.0.1

- Initial release of `dart_accuraterip_cli`.
- Standalone command-line interface wrapping the
  [`dart_accuraterip`](https://pub.dev/packages/dart_accuraterip)
  library. Installs as `dart-accuraterip` on the user's PATH via
  `dart pub global activate dart_accuraterip_cli`.
- Subcommands:
  - `crc` — compute AccurateRip v1 and v2 CRCs over a single
    WAV file, with optional `--first` / `--last` lead-in and
    lead-out skip flags.
  - `disc-id` — compute an AccurateRip disc ID (discId1, discId2,
    cddbDiscId) from a list of WAV files given in track order,
    and print the built database URL.
  - `verify` — end-to-end verification of a rip against the live
    AccurateRip database. Loads every WAV, computes v1 and v2,
    queries the database, and prints a PASS/FAIL table.
  - `query` — fetch and pretty-print the raw AccurateRip database
    response for a disc ID, no audio required. Useful for
    protocol debugging.
- Hand-rolled argument parser and `dart:io` `HttpClient` so the
  CLI package has **zero runtime dependencies beyond the library
  itself**.
- WAV only for audio input in this release; FLAC support is
  planned for a future round.
