// Tests for the lib/src/wav.dart helpers: extractPcmFromWav plus
// the computeArV1FromWav / computeArV2FromWav wrappers.
//
// The fixtures here are tiny synthetic WAV files built in-memory —
// small enough that the expected CRCs are derivable from the
// existing computeArV1/computeArV2 tests.

import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:test/test.dart';

/// Build a minimal but well-formed RIFF/WAVE file containing the
/// given raw PCM bytes. 16-bit stereo, 44.1 kHz, mono `fmt ` + `data`.
Uint8List buildSimpleWav(Uint8List pcm) {
  final builder = BytesBuilder();

  // --- RIFF header ---
  builder.add(ascii('RIFF'));
  builder.add(_u32le(36 + pcm.length)); // file size − 8
  builder.add(ascii('WAVE'));

  // --- fmt chunk (16 bytes for PCM) ---
  builder.add(ascii('fmt '));
  builder.add(_u32le(16)); // chunk size
  builder.add(_u16le(1)); // PCM format
  builder.add(_u16le(2)); // channels = 2 (stereo)
  builder.add(_u32le(44100)); // sample rate
  builder.add(
      _u32le(44100 * 4)); // byte rate (sample_rate * num_channels * bits/8)
  builder.add(_u16le(4)); // block align (num_channels * bits/8)
  builder.add(_u16le(16)); // bits per sample

  // --- data chunk ---
  builder.add(ascii('data'));
  builder.add(_u32le(pcm.length));
  builder.add(pcm);

  return builder.toBytes();
}

/// Same as [buildSimpleWav] but also sneaks a junk `LIST` chunk
/// between `fmt ` and `data`, to prove the chunk walker is tolerant.
Uint8List buildWavWithExtraListChunk(Uint8List pcm) {
  final builder = BytesBuilder();

  builder.add(ascii('RIFF'));
  // 36 bytes of fmt + 8 bytes of LIST header + LIST payload + 8 bytes of data header + pcm.
  const listPayload = <int>[0, 1, 2, 3, 4, 5, 6, 7]; // 8 bytes
  builder.add(
    _u32le(36 + (8 + listPayload.length) + pcm.length),
  );
  builder.add(ascii('WAVE'));

  builder.add(ascii('fmt '));
  builder.add(_u32le(16));
  builder.add(_u16le(1));
  builder.add(_u16le(2));
  builder.add(_u32le(44100));
  builder.add(_u32le(44100 * 4));
  builder.add(_u16le(4));
  builder.add(_u16le(16));

  builder.add(ascii('LIST'));
  builder.add(_u32le(listPayload.length));
  builder.add(listPayload);

  builder.add(ascii('data'));
  builder.add(_u32le(pcm.length));
  builder.add(pcm);

  return builder.toBytes();
}

List<int> ascii(String s) => s.codeUnits;
List<int> _u16le(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32le(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];

void main() {
  // Build a 4-frame synthetic PCM whose direct CRC is hand-computed
  // in the existing CRC tests: samples [1, 2, 3, 4] → crc v1 = 30.
  Uint8List fourFramePcm() {
    final bytes = ByteData(16);
    bytes.setUint32(0, 1, Endian.little);
    bytes.setUint32(4, 2, Endian.little);
    bytes.setUint32(8, 3, Endian.little);
    bytes.setUint32(12, 4, Endian.little);
    return bytes.buffer.asUint8List();
  }

  group('extractPcmFromWav', () {
    test('returns the data chunk payload from a simple PCM WAV', () {
      final pcm = fourFramePcm();
      final wav = buildSimpleWav(pcm);

      final extracted = extractPcmFromWav(wav);

      expect(extracted, equals(pcm));
    });

    test('tolerates extra chunks (LIST) between fmt and data', () {
      final pcm = fourFramePcm();
      final wav = buildWavWithExtraListChunk(pcm);

      final extracted = extractPcmFromWav(wav);

      expect(extracted, equals(pcm));
    });

    test('throws FormatException on a non-RIFF file', () {
      final notAWav = Uint8List.fromList([
        ...ascii('NOPE'),
        ..._u32le(0),
        ...ascii('XXXX'),
      ]);

      expect(
        () => extractPcmFromWav(notAWav),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when there is no data chunk', () {
      final builder = BytesBuilder();
      builder.add(ascii('RIFF'));
      builder.add(_u32le(20));
      builder.add(ascii('WAVE'));
      builder.add(ascii('fmt '));
      builder.add(_u32le(16));
      builder.add(_u16le(1));
      builder.add(_u16le(2));
      builder.add(_u32le(44100));
      builder.add(_u32le(44100 * 4));
      builder.add(_u16le(4));
      builder.add(_u16le(16));

      expect(
        () => extractPcmFromWav(builder.toBytes()),
        throwsA(isA<FormatException>()),
      );
    });

    test('tolerates a truncated trailing data chunk', () {
      // Declare 16 bytes in the data header but only supply 8 — a
      // real capture can be truncated mid-write. The helper should
      // return whatever bytes are actually present rather than
      // crashing.
      final builder = BytesBuilder();
      builder.add(ascii('RIFF'));
      builder.add(_u32le(0)); // size does not matter for our walker
      builder.add(ascii('WAVE'));
      builder.add(ascii('fmt '));
      builder.add(_u32le(16));
      builder.add(_u16le(1));
      builder.add(_u16le(2));
      builder.add(_u32le(44100));
      builder.add(_u32le(44100 * 4));
      builder.add(_u16le(4));
      builder.add(_u16le(16));
      builder.add(ascii('data'));
      builder.add(_u32le(16)); // claims 16 bytes
      builder.add(List<int>.filled(8, 0xAB)); // only 8 present

      final out = extractPcmFromWav(builder.toBytes());
      expect(out.length, equals(8));
      expect(out.every((b) => b == 0xAB), isTrue);
    });
  });

  group('computeArV1FromWav / computeArV2FromWav', () {
    test('produce the same CRC as computeArV1/computeArV2 on raw PCM', () {
      final pcm = fourFramePcm();
      final wav = buildSimpleWav(pcm);

      expect(computeArV1FromWav(wav), equals(computeArV1(pcm)));
      expect(computeArV2FromWav(wav), equals(computeArV2(pcm)));
    });

    test('propagate isFirstTrack / isLastTrack flags', () {
      // 2945 samples with values 1..2945 — same fixture as the
      // existing first-track / last-track tests in the CRC suite.
      final values = List<int>.generate(2945, (i) => i + 1);
      final pcmBytes = ByteData(values.length * 4);
      for (var i = 0; i < values.length; i++) {
        pcmBytes.setUint32(i * 4, values[i], Endian.little);
      }
      final pcm = pcmBytes.buffer.asUint8List();
      final wav = buildSimpleWav(pcm);

      expect(
        computeArV1FromWav(wav, isFirstTrack: true),
        equals(computeArV1(pcm, isFirstTrack: true)),
      );
      expect(
        computeArV1FromWav(wav, isLastTrack: true),
        equals(computeArV1(pcm, isLastTrack: true)),
      );
    });
  });
}
