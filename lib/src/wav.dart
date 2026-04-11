/// WAV (RIFF/WAVE) input helpers.
///
/// The core CRC and disc-ID functions in this library operate on
/// raw PCM bytes — 16-bit signed little-endian stereo interleaved.
/// This file adds three conveniences for the very common case of
/// "I have a `.wav` file on disk and want its AccurateRip CRC":
///
///  - [extractPcmFromWav] finds the `data` chunk inside a
///    RIFF/WAVE byte buffer and returns its payload, tolerating
///    extra chunks (LIST, INFO, fact) between `fmt ` and `data`.
///  - [computeArV1FromWav] and [computeArV2FromWav] combine
///    [extractPcmFromWav] with [computeArV1] / [computeArV2] so
///    callers can skip the intermediate PCM variable.
///
/// These helpers do no file I/O of their own — pass in the raw
/// bytes (`File(path).readAsBytesSync()` is the typical caller).
/// That keeps the library pure and lets the web-safe call sites
/// (the RIFF walker itself) stay web-safe; the CRC functions keep
/// their usual "Dart VM / Flutter native only" constraint.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:typed_data';

import 'accuraterip_crc.dart';

/// Strip the WAV header from [wavBytes] and return the raw PCM
/// payload (the bytes inside the first `data` chunk).
///
/// Walks the RIFF chunk list starting at offset 12, tolerating
/// extra chunks (`LIST`, `INFO`, `fact`, `bext`, …) between the
/// `fmt ` chunk and the `data` chunk. Handles odd chunk sizes by
/// skipping the mandatory 1-byte padding that follows them.
///
/// If the `data` chunk header declares more bytes than are
/// actually present in [wavBytes] (i.e. a truncated trailing
/// chunk), the returned slice is whatever remains — mirroring the
/// tolerant behaviour of [parseAccurateRipResponse] on short
/// responses.
///
/// Throws [FormatException] when [wavBytes] does not begin with
/// `RIFF....WAVE` or when no `data` chunk is found. The caller
/// chose the file explicitly, so a loud error is more useful than
/// a silent `null`.
Uint8List extractPcmFromWav(Uint8List wavBytes) {
  if (wavBytes.length < 12 ||
      _ascii(wavBytes, 0, 4) != 'RIFF' ||
      _ascii(wavBytes, 8, 12) != 'WAVE') {
    throw const FormatException(
      'not a RIFF/WAVE file: missing RIFF/WAVE signature',
    );
  }

  var pos = 12;
  while (pos + 8 <= wavBytes.length) {
    final id = _ascii(wavBytes, pos, pos + 4);
    final size = ByteData.sublistView(
      wavBytes,
      pos + 4,
      pos + 8,
    ).getUint32(0, Endian.little);
    final payloadStart = pos + 8;
    final payloadEnd = payloadStart + size;

    if (id == 'data') {
      if (payloadEnd > wavBytes.length) {
        // Tolerate a truncated trailing data chunk — return what
        // we actually have rather than throwing.
        return Uint8List.sublistView(wavBytes, payloadStart);
      }
      return Uint8List.sublistView(wavBytes, payloadStart, payloadEnd);
    }

    // Chunks are padded to even size. If `size` is odd, skip one
    // extra byte of padding.
    pos = payloadEnd + (size & 1);
  }

  throw const FormatException(
    'no "data" chunk found in WAV stream',
  );
}

/// Compute the AccurateRip v1 CRC of a WAV file's PCM payload.
///
/// Convenience wrapper: `computeArV1(extractPcmFromWav(wavBytes), …)`.
///
/// Throws [FormatException] on malformed WAV input. See
/// [computeArV1] for the platform caveats (native 64-bit int only,
/// unsafe on dart2js / WASM).
int computeArV1FromWav(
  Uint8List wavBytes, {
  bool isFirstTrack = false,
  bool isLastTrack = false,
}) {
  final pcm = extractPcmFromWav(wavBytes);
  return computeArV1(
    pcm,
    isFirstTrack: isFirstTrack,
    isLastTrack: isLastTrack,
  );
}

/// Compute the AccurateRip v2 CRC of a WAV file's PCM payload.
///
/// Convenience wrapper: `computeArV2(extractPcmFromWav(wavBytes), …)`.
///
/// Throws [FormatException] on malformed WAV input. See
/// [computeArV2] for the platform caveats (native 64-bit int only,
/// unsafe on dart2js / WASM).
int computeArV2FromWav(
  Uint8List wavBytes, {
  bool isFirstTrack = false,
  bool isLastTrack = false,
}) {
  final pcm = extractPcmFromWav(wavBytes);
  return computeArV2(
    pcm,
    isFirstTrack: isFirstTrack,
    isLastTrack: isLastTrack,
  );
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));
