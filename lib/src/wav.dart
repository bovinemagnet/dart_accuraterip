/// WAV (RIFF/WAVE) input helpers.
///
/// The core CRC and disc-ID functions in this library operate on
/// raw PCM bytes — 16-bit signed little-endian stereo interleaved.
/// This file adds conveniences for the very common case of
/// "I have a `.wav` file on disk and want its AccurateRip CRC":
///
///  - [extractPcmFromWav] finds the `data` chunk inside a
///    RIFF/WAVE byte buffer and returns its payload, tolerating
///    extra chunks (LIST, INFO, fact) between `fmt ` and `data`.
///  - [parseWavFormat] reads the `fmt ` chunk into a [WavFormat],
///    whose [WavFormat.requireRedBookCdAudio] rejects audio that
///    AccurateRip is not defined for (anything other than 16-bit
///    stereo 44.1 kHz integer PCM).
///  - [computeArV1FromWav] and [computeArV2FromWav] combine the
///    Red Book check, [extractPcmFromWav], and [computeArV1] /
///    [computeArV2] so callers can skip the intermediate steps.
///
/// These helpers do no file I/O of their own — pass in the raw
/// bytes (`File(path).readAsBytesSync()` is the typical caller).
/// Everything here runs on every Dart platform; the CRC functions
/// are selected via the same conditional import the public barrel
/// uses, so the wrappers are correct on VM and web alike.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:typed_data';

// Pick the same CRC implementation the public barrel does, so the
// FromWav wrappers are correct on both VM and web.
import 'accuraterip_crc_io.dart'
    if (dart.library.js_interop) 'accuraterip_crc_web.dart';

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
  final chunk = _findChunk(wavBytes, 'data');
  if (chunk == null) {
    throw const FormatException(
      'no "data" chunk found in WAV stream',
    );
  }

  final payloadEnd = chunk.start + chunk.size;
  if (payloadEnd > wavBytes.length) {
    // Tolerate a truncated trailing data chunk — return what
    // we actually have rather than throwing.
    return Uint8List.sublistView(wavBytes, chunk.start);
  }
  return Uint8List.sublistView(wavBytes, chunk.start, payloadEnd);
}

/// The audio format declared by a WAV file's `fmt ` chunk.
///
/// Returned by [parseWavFormat]. AccurateRip checksums are defined
/// only for Red Book CD-DA audio; use [requireRedBookCdAudio] (or
/// [isRedBookCdAudio]) before checksumming a WAV whose provenance
/// is not already known.
class WavFormat {
  /// Create a [WavFormat] with the given field values.
  const WavFormat({
    required this.formatCode,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
  });

  /// The WAVE format tag. `1` is integer PCM; other common values
  /// are `3` (IEEE float) and `0xFFFE` (WAVE_FORMAT_EXTENSIBLE).
  final int formatCode;

  /// Number of interleaved channels.
  final int channels;

  /// Sample rate in Hz.
  final int sampleRate;

  /// Bits per sample per channel.
  final int bitsPerSample;

  /// Whether this is Red Book CD-DA audio — integer PCM
  /// (format 1), 2 channels, 44 100 Hz, 16-bit — the only format
  /// AccurateRip checksums are defined for.
  ///
  /// Note this is deliberately strict: a WAVE_FORMAT_EXTENSIBLE
  /// header wrapping PCM is rejected even though its payload may
  /// be CD audio, because rippers write plain format-1 headers.
  bool get isRedBookCdAudio =>
      formatCode == 1 &&
      channels == 2 &&
      sampleRate == 44100 &&
      bitsPerSample == 16;

  /// Throw [ArgumentError] unless [isRedBookCdAudio].
  ///
  /// The error message names every non-conforming field so the
  /// caller can report exactly why the file was rejected.
  void requireRedBookCdAudio() {
    if (isRedBookCdAudio) return;
    final problems = <String>[
      if (formatCode != 1) 'format code $formatCode (expected 1, integer PCM)',
      if (channels != 2) '$channels channel(s) (expected 2)',
      if (sampleRate != 44100) '$sampleRate Hz (expected 44100)',
      if (bitsPerSample != 16) '$bitsPerSample bits per sample (expected 16)',
    ];
    throw ArgumentError(
      'not Red Book CD-DA audio: ${problems.join(', ')}. '
      'AccurateRip checksums are defined only for 16-bit stereo '
      '44.1 kHz integer PCM.',
    );
  }

  @override
  String toString() => 'WavFormat(formatCode: $formatCode, '
      'channels: $channels, sampleRate: $sampleRate, '
      'bitsPerSample: $bitsPerSample)';
}

/// Read the `fmt ` chunk of [wavBytes] into a [WavFormat].
///
/// Throws [FormatException] when [wavBytes] does not begin with
/// `RIFF....WAVE`, has no `fmt ` chunk, or declares a `fmt ` chunk
/// shorter than the 16 bytes the base fields occupy.
WavFormat parseWavFormat(Uint8List wavBytes) {
  final chunk = _findChunk(wavBytes, 'fmt ');
  if (chunk == null) {
    throw const FormatException(
      'no "fmt " chunk found in WAV stream',
    );
  }
  if (chunk.size < 16 || chunk.start + 16 > wavBytes.length) {
    throw const FormatException(
      '"fmt " chunk too short: need at least 16 bytes',
    );
  }

  final fields = ByteData.sublistView(wavBytes, chunk.start, chunk.start + 16);
  return WavFormat(
    formatCode: fields.getUint16(0, Endian.little),
    channels: fields.getUint16(2, Endian.little),
    sampleRate: fields.getUint32(4, Endian.little),
    bitsPerSample: fields.getUint16(14, Endian.little),
  );
}

/// Locate the first chunk with the given four-character [id] and
/// return its payload start offset and declared size.
///
/// Shared by [extractPcmFromWav] and [parseWavFormat] so the two
/// walkers can never drift apart. Validates the `RIFF....WAVE`
/// signature (throws [FormatException] when absent), tolerates
/// unknown chunks, and honours the odd-size padding rule. Returns
/// `null` when no chunk matches; the declared size may extend past
/// the end of [wavBytes] for a truncated trailing chunk — callers
/// decide how tolerant to be.
({int start, int size})? _findChunk(Uint8List wavBytes, String id) {
  if (wavBytes.length < 12 ||
      _ascii(wavBytes, 0, 4) != 'RIFF' ||
      _ascii(wavBytes, 8, 12) != 'WAVE') {
    throw const FormatException(
      'not a RIFF/WAVE file: missing RIFF/WAVE signature',
    );
  }

  var pos = 12;
  while (pos + 8 <= wavBytes.length) {
    final chunkId = _ascii(wavBytes, pos, pos + 4);
    final size = ByteData.sublistView(
      wavBytes,
      pos + 4,
      pos + 8,
    ).getUint32(0, Endian.little);

    if (chunkId == id) {
      return (start: pos + 8, size: size);
    }

    // Chunks are padded to even size. If `size` is odd, skip one
    // extra byte of padding.
    pos = pos + 8 + size + (size & 1);
  }

  return null;
}

/// Compute the AccurateRip v1 CRC of a WAV file's PCM payload.
///
/// Convenience wrapper:
/// `parseWavFormat(wavBytes).requireRedBookCdAudio()` followed by
/// `computeArV1(extractPcmFromWav(wavBytes), …)`.
///
/// Throws [FormatException] on malformed WAV input and
/// [ArgumentError] when the WAV is not Red Book CD-DA (16-bit
/// stereo 44.1 kHz integer PCM) — AccurateRip checksums are not
/// defined for any other format, so checksumming one silently
/// would produce a plausible-looking but meaningless value. Use
/// [extractPcmFromWav] + [computeArV1] directly to bypass the
/// check.
int computeArV1FromWav(
  Uint8List wavBytes, {
  bool isFirstTrack = false,
  bool isLastTrack = false,
}) {
  parseWavFormat(wavBytes).requireRedBookCdAudio();
  final pcm = extractPcmFromWav(wavBytes);
  return computeArV1(
    pcm,
    isFirstTrack: isFirstTrack,
    isLastTrack: isLastTrack,
  );
}

/// Compute the AccurateRip v2 CRC of a WAV file's PCM payload.
///
/// Convenience wrapper:
/// `parseWavFormat(wavBytes).requireRedBookCdAudio()` followed by
/// `computeArV2(extractPcmFromWav(wavBytes), …)`.
///
/// Throws [FormatException] on malformed WAV input and
/// [ArgumentError] when the WAV is not Red Book CD-DA — see
/// [computeArV1FromWav] for the rationale and the bypass.
int computeArV2FromWav(
  Uint8List wavBytes, {
  bool isFirstTrack = false,
  bool isLastTrack = false,
}) {
  parseWavFormat(wavBytes).requireRedBookCdAudio();
  final pcm = extractPcmFromWav(wavBytes);
  return computeArV2(
    pcm,
    isFirstTrack: isFirstTrack,
    isLastTrack: isLastTrack,
  );
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));
