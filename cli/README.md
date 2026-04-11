# dart_accuraterip_cli

Standalone command-line interface for the
[`dart_accuraterip`](https://pub.dev/packages/dart_accuraterip)
library. Computes AccurateRip v1/v2 CRCs, disc IDs, and verifies
ripped WAV files against the live AccurateRip database, with
**zero runtime dependencies** beyond the library itself (no
`package:args`, no `package:http` — just hand-rolled argument
parsing and `dart:io`'s built-in `HttpClient`).

## Installation

```sh
dart pub global activate dart_accuraterip_cli
```

This puts `dart-accuraterip` on your `PATH` (assuming
`$HOME/.pub-cache/bin` is already there).

For local development against a checkout of the repo:

```sh
dart pub global activate --source path ./cli
```

## Usage

```
dart-accuraterip --help
dart-accuraterip --version

dart-accuraterip crc     [--first] [--last] <file.wav>
dart-accuraterip disc-id <file1.wav> <file2.wav> ...
dart-accuraterip verify  <file1.wav> <file2.wav> ...
dart-accuraterip query   <discId1-hex> <discId2-hex> <cddbId-hex> <trackCount>
```

### `crc` — compute v1 and v2 for one file

```sh
$ dart-accuraterip crc --first track01.wav
v1: 284fc705
v2: dc77f9ab
```

Use `--first` / `--last` to skip the 2940-sample CD lead-in /
lead-out region for the first and/or last track on the disc.
Without the flags the full PCM is checksummed.

### `disc-id` — compute a disc ID from a rip

```sh
$ dart-accuraterip disc-id track01.wav track02.wav track03.wav
discId1:    0x0000f21c
discId2:    0x00027ef8
cddbDiscId: 0x05021002
trackCount: 3
url:        http://www.accuraterip.com/accuraterip/c/1/2/dBAR-003-...
```

Positional order is track order. If your rips are named
lexically (`track01.wav`, `track02.wav`, …) the shell's glob
expansion is enough: `dart-accuraterip disc-id track*.wav`.

### `verify` — end-to-end rip verification

```sh
$ dart-accuraterip verify track*.wav
track  v1         v2         db match    max-conf  result
-----  ---------  ---------  ----------  --------  ------
01     284fc705   dc77f9ab   v1 matched  12        PASS
02     9cc1f32e   dd97d2c3   v1 matched  20        PASS

All tracks verified.
```

Loads each WAV, computes v1/v2 with the correct first/last skip
flags, computes the disc ID, queries the database, and for each
track checks whether either locally computed CRC equals any
entry's stored CRC (see
[`AccurateRipEntry.matches`](https://pub.dev/documentation/dart_accuraterip/latest/dart_accuraterip/AccurateRipEntry/matches.html)).
Exits with status 1 on any mismatch so you can wire it into a
shell pipeline.

### `query` — raw database lookup, no audio

```sh
$ dart-accuraterip query 0000f21c 00027ef8 05021002 2
```

Useful for debugging disc-ID computation in another tool or
inspecting the raw database response for a known disc.

## FLAC support

**Not yet.** This release is WAV only. If your rip is in FLAC,
either:

- decode to WAV first with `flac -d track01.flac` and run the CLI
  on the result, or
- use the developer-only
  [`tool/verify_disc.dart`](../tool/verify_disc.dart) script in
  the parent repository, which shells out to the `flac` CLI to
  decode on the fly.

FLAC support inside this CLI is planned for a later round.

## Platform support

Dart VM / Flutter native only (Android, iOS, macOS, Windows,
Linux). The underlying CRC functions rely on native 64-bit
integer arithmetic and will produce wrong results under dart2js
/ WASM. See the main library's README for the platform-support
matrix.

## Licence

[GNU General Public License v3.0](LICENSE), matching the parent
library.
