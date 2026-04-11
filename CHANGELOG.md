# Changelog

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
