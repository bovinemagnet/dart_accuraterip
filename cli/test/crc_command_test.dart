// Integration tests for the `crc` subcommand.
//
// These tests build tiny synthetic WAV files on disk, invoke
// `runCrc` directly with an injected IOSink, and assert that the
// printed hex CRCs match what `computeArV1` / `computeArV2`
// produce on the same raw PCM. This pins both the WAV-loading
// plumbing and the skip-flag wiring without forking a subprocess.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:dart_accuraterip_cli/src/commands/crc.dart';
import 'package:test/test.dart';

/// Build a minimal stereo 16-bit WAV wrapping [pcm].
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

List<int> _u16le(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32le(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];

Uint8List buildFourFramePcm() {
  final bytes = ByteData(16);
  bytes.setUint32(0, 1, Endian.little);
  bytes.setUint32(4, 2, Endian.little);
  bytes.setUint32(8, 3, Endian.little);
  bytes.setUint32(12, 4, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('darar_cli_crc_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  String writeWav(String name, Uint8List wav) {
    final path = '${tmpDir.path}/$name';
    File(path).writeAsBytesSync(wav);
    return path;
  }

  group('runCrc', () {
    test('prints v1 and v2 matching computeArV1/computeArV2 with no flags',
        () async {
      final pcm = buildFourFramePcm();
      final path = writeWav('track.wav', buildSimpleWav(pcm));
      final buffer = StringBuffer();

      final exit = await runCrc([path], _bufferSink(buffer));

      expect(exit, equals(0));
      final expectedV1 = computeArV1(pcm).toRadixString(16).padLeft(8, '0');
      final expectedV2 = computeArV2(pcm).toRadixString(16).padLeft(8, '0');
      expect(buffer.toString(), contains('v1: $expectedV1'));
      expect(buffer.toString(), contains('v2: $expectedV2'));
    });

    test('propagates --first to the CRC functions', () async {
      // 2945 samples — same fixture shape as the library's
      // first-track skip test. The skipped CRC differs from the
      // non-skipped one, so a missing flag would silently produce
      // the wrong output.
      final values = List<int>.generate(2945, (i) => i + 1);
      final pcmBytes = ByteData(values.length * 4);
      for (var i = 0; i < values.length; i++) {
        pcmBytes.setUint32(i * 4, values[i], Endian.little);
      }
      final pcm = pcmBytes.buffer.asUint8List();
      final path = writeWav('first.wav', buildSimpleWav(pcm));
      final buffer = StringBuffer();

      final exit = await runCrc(['--first', path], _bufferSink(buffer));

      expect(exit, equals(0));
      final expectedV1 = computeArV1(pcm, isFirstTrack: true)
          .toRadixString(16)
          .padLeft(8, '0');
      expect(buffer.toString(), contains('v1: $expectedV1'));
    });

    test('returns non-zero and prints usage on zero positional args', () async {
      final buffer = StringBuffer();
      final exit = await runCrc(<String>[], _bufferSink(buffer));
      expect(exit, isNot(equals(0)));
    });

    test('returns non-zero when the file does not exist', () async {
      final buffer = StringBuffer();
      final exit = await runCrc(
        ['${tmpDir.path}/does_not_exist.wav'],
        _bufferSink(buffer),
      );
      expect(exit, isNot(equals(0)));
    });

    test('--help returns zero and prints usage', () async {
      final buffer = StringBuffer();
      final exit = await runCrc(['--help'], _bufferSink(buffer));
      expect(exit, equals(0));
      expect(buffer.toString().toLowerCase(), contains('usage'));
    });
  });
}

/// Build an [IOSink] that writes into [buffer] for test assertions.
IOSink _bufferSink(StringBuffer buffer) {
  final controller = _StringBufferIOSink(buffer);
  return controller;
}

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
