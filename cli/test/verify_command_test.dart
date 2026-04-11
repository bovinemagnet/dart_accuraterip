// Integration tests for the `verify` subcommand.
//
// These tests build tiny synthetic WAVs, stub the fetcher with a
// closure that returns a hand-built AccurateRip response chunk,
// and assert that `runVerify` PASSes when the chunk contains a
// matching CRC and FAILs when it doesn't.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:dart_accuraterip_cli/src/commands/verify.dart';
import 'package:test/test.dart';

// --- WAV + chunk builders ---------------------------------------------------

Uint8List buildSimpleWav(Uint8List pcm) {
  final builder = BytesBuilder();
  builder.add('RIFF'.codeUnits);
  builder.add(_u32le(36 + pcm.length));
  builder.add('WAVE'.codeUnits);
  builder.add('fmt '.codeUnits);
  builder.add(_u32le(16));
  builder.add(_u16le(1));
  builder.add(_u16le(2));
  builder.add(_u32le(44100));
  builder.add(_u32le(44100 * 4));
  builder.add(_u16le(4));
  builder.add(_u16le(16));
  builder.add('data'.codeUnits);
  builder.add(_u32le(pcm.length));
  builder.add(pcm);
  return builder.toBytes();
}

Uint8List buildChunk({
  required int discId1,
  required int discId2,
  required int cddbDiscId,
  required List<({int confidence, int crc, int frame450Crc})> tracks,
}) {
  final builder = BytesBuilder();
  builder.addByte(tracks.length);
  builder.add(_u32le(discId1));
  builder.add(_u32le(discId2));
  builder.add(_u32le(cddbDiscId));
  for (final t in tracks) {
    builder.addByte(t.confidence);
    builder.add(_u32le(t.crc));
    builder.add(_u32le(t.frame450Crc));
  }
  return builder.toBytes();
}

List<int> _u16le(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32le(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];

Uint8List buildPcm(int sampleCount, {int seed = 1}) {
  final bytes = ByteData(sampleCount * 4);
  for (var i = 0; i < sampleCount; i++) {
    bytes.setUint32(i * 4, (seed + i) & 0xFFFFFFFF, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

// --- tests ------------------------------------------------------------------

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('darar_cli_verify_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  String writeWav(String name, Uint8List wav) {
    final path = '${tmpDir.path}/$name';
    File(path).writeAsBytesSync(wav);
    return path;
  }

  group('runVerify', () {
    test(
        'PASSes when the fetcher returns an entry whose CRC matches the '
        'locally computed v1', () async {
      // Single-track rip — 1000 frames, seeded.
      final pcm = buildPcm(1000);
      final path = writeWav('track.wav', buildSimpleWav(pcm));

      // Single-track disc: isFirstTrack && isLastTrack.
      final localV1 = computeArV1(pcm, isFirstTrack: true, isLastTrack: true);
      final localV2 = computeArV2(pcm, isFirstTrack: true, isLastTrack: true);

      final expectedId = AccurateRipDiscId.fromTrackSampleCounts([1000]);

      // Stub fetcher returning a chunk whose `crc` matches local v1.
      final fakeResponse = buildChunk(
        discId1: expectedId.discId1,
        discId2: expectedId.discId2,
        cddbDiscId: expectedId.cddbDiscId,
        tracks: [(confidence: 99, crc: localV1, frame450Crc: 0)],
      );

      final buffer = StringBuffer();
      final exit = await runVerify(
        [path],
        _bufferSink(buffer),
        fetcher: (_) async => fakeResponse,
      );

      expect(exit, equals(0));
      expect(buffer.toString(), contains('PASS'));
      expect(buffer.toString(), contains('All tracks verified'));
      // v2 is printed even though v1 matched first.
      expect(buffer.toString(), contains(_hex8(localV2)));
    });

    test('PASSes when the match is via local v2 instead of v1', () async {
      final pcm = buildPcm(1000, seed: 17);
      final path = writeWav('track.wav', buildSimpleWav(pcm));

      final localV1 = computeArV1(pcm, isFirstTrack: true, isLastTrack: true);
      final localV2 = computeArV2(pcm, isFirstTrack: true, isLastTrack: true);
      final expectedId = AccurateRipDiscId.fromTrackSampleCounts([1000]);

      // Make the stored CRC match local v2 — simulating a
      // pressing submitted by a v2-era ripper.
      final fakeResponse = buildChunk(
        discId1: expectedId.discId1,
        discId2: expectedId.discId2,
        cddbDiscId: expectedId.cddbDiscId,
        tracks: [(confidence: 42, crc: localV2, frame450Crc: 0)],
      );

      final buffer = StringBuffer();
      final exit = await runVerify(
        [path],
        _bufferSink(buffer),
        fetcher: (_) async => fakeResponse,
      );

      expect(exit, equals(0));
      expect(buffer.toString(), contains('PASS'));
      expect(buffer.toString(), contains(_hex8(localV1)));
    });

    test('FAILs when no pressing matches', () async {
      final pcm = buildPcm(1000, seed: 99);
      final path = writeWav('track.wav', buildSimpleWav(pcm));
      final expectedId = AccurateRipDiscId.fromTrackSampleCounts([1000]);

      final fakeResponse = buildChunk(
        discId1: expectedId.discId1,
        discId2: expectedId.discId2,
        cddbDiscId: expectedId.cddbDiscId,
        tracks: [(confidence: 10, crc: 0xDEADBEEF, frame450Crc: 0)],
      );

      final buffer = StringBuffer();
      final exit = await runVerify(
        [path],
        _bufferSink(buffer),
        fetcher: (_) async => fakeResponse,
      );

      expect(exit, isNot(equals(0)));
      expect(buffer.toString(), contains('FAIL'));
    });

    test('returns non-zero when the database has no entry for the disc',
        () async {
      final pcm = buildPcm(500);
      final path = writeWav('track.wav', buildSimpleWav(pcm));

      final buffer = StringBuffer();
      final exit = await runVerify(
        [path],
        _bufferSink(buffer),
        fetcher: (_) async => Uint8List(0),
      );

      expect(exit, isNot(equals(0)));
      expect(
        buffer.toString().toLowerCase(),
        contains('no entry'),
      );
    });

    test('--help returns zero and prints usage', () async {
      final buffer = StringBuffer();
      final exit = await runVerify(
        ['--help'],
        _bufferSink(buffer),
        fetcher: (_) async => Uint8List(0),
      );
      expect(exit, equals(0));
      expect(buffer.toString().toLowerCase(), contains('usage'));
    });
  });
}

String _hex8(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

IOSink _bufferSink(StringBuffer buffer) => _StringBufferIOSink(buffer);

class _StringBufferIOSink implements IOSink {
  _StringBufferIOSink(this.buffer);
  final StringBuffer buffer;

  @override
  void write(Object? obj) => buffer.write(obj);

  @override
  void writeln([Object? obj = '']) => buffer.writeln(obj);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => buffer.write(String.fromCharCodes(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Future flush() async {}

  @override
  Encoding get encoding => systemEncoding;

  @override
  set encoding(Encoding value) {}
}
