# Changelog

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
