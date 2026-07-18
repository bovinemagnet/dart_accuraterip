// Integration tests for the `disc-id` subcommand.
//
// Builds tiny synthetic WAVs with known sample counts, invokes
// runDiscId, and asserts the printed disc ID matches
// AccurateRipDiscId.fromTrackSampleCounts on the same counts.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';
import 'package:dart_accuraterip_cli/src/commands/disc_id.dart';
import 'package:test/test.dart';

Uint8List buildSimpleWav(Uint8List pcm) => buildWav(pcm: pcm);

/// Build a configurable WAV. Defaults are Red Book CD-DA. Tests that
/// want to feed a non-Red-Book file to the CLI override individual
/// arguments.
Uint8List buildWav({
  required Uint8List pcm,
  int channels = 2,
  int sampleRate = 44100,
  int bitsPerSample = 16,
  int audioFormat = 1,
}) {
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final byteRate = sampleRate * blockAlign;
  final builder = BytesBuilder();
  builder.add('RIFF'.codeUnits);
  builder.add(_u32le(36 + pcm.length));
  builder.add('WAVE'.codeUnits);
  builder.add('fmt '.codeUnits);
  builder.add(_u32le(16));
  builder.add(_u16le(audioFormat));
  builder.add(_u16le(channels));
  builder.add(_u32le(sampleRate));
  builder.add(_u32le(byteRate));
  builder.add(_u16le(blockAlign));
  builder.add(_u16le(bitsPerSample));
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

/// Build raw PCM containing [sampleCount] stereo frames. The
/// actual sample values don't matter for disc-ID computation —
/// only the length does.
Uint8List buildPcmOfLength(int sampleCount) => Uint8List(sampleCount * 4);

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('darar_cli_discid_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  String writeWav(String name, int sampleCount) {
    final path = '${tmpDir.path}/$name';
    File(path).writeAsBytesSync(buildSimpleWav(buildPcmOfLength(sampleCount)));
    return path;
  }

  group('runDiscId', () {
    test('prints the disc ID matching fromTrackSampleCounts', () async {
      // Four 1-minute tracks: 60 * 44100 = 2_646_000 samples each.
      const counts = <int>[2646000, 2646000, 2646000, 2646000];
      final paths = [
        writeWav('01.wav', counts[0]),
        writeWav('02.wav', counts[1]),
        writeWav('03.wav', counts[2]),
        writeWav('04.wav', counts[3]),
      ];

      final buffer = StringBuffer();
      final exit = await runDiscId(paths, _bufferSink(buffer));
      expect(exit, equals(0));

      final expected = AccurateRipDiscId.fromTrackSampleCounts(counts);
      expect(
        buffer.toString(),
        contains(
          'discId1:    0x${expected.discId1.toRadixString(16).padLeft(8, '0')}',
        ),
      );
      expect(
        buffer.toString(),
        contains(
          'discId2:    0x${expected.discId2.toRadixString(16).padLeft(8, '0')}',
        ),
      );
      expect(
        buffer.toString(),
        contains(
          'cddbDiscId: 0x'
          '${expected.cddbDiscId.toRadixString(16).padLeft(8, '0')}',
        ),
      );
      expect(buffer.toString(), contains('trackCount: 4'));
      expect(
        buffer.toString(),
        contains('url:        ${buildAccurateRipUrl(expected)}'),
      );
    });

    test('returns non-zero when given zero positional args', () async {
      final buffer = StringBuffer();
      final exit = await runDiscId(<String>[], _bufferSink(buffer));
      expect(exit, isNot(equals(0)));
    });

    test('rejects a 48 kHz / mono WAV with a usage exit code', () async {
      // Mono 48 kHz, 16-bit — looks valid as a RIFF/WAVE file but
      // is not Red Book CD-DA, so AccurateRip is undefined for it.
      // The CLI must refuse rather than print a meaningless ID.
      final path = '${tmpDir.path}/wrong.wav';
      File(path).writeAsBytesSync(
        buildWav(
          pcm: Uint8List(44100 * 2 * 1),
          channels: 1,
          sampleRate: 48000,
        ),
      );

      final buffer = StringBuffer();
      final exit = await runDiscId([path], _bufferSink(buffer));
      expect(exit, equals(64));
    });

    test('--help returns zero and prints usage', () async {
      final buffer = StringBuffer();
      final exit = await runDiscId(['--help'], _bufferSink(buffer));
      expect(exit, equals(0));
      expect(buffer.toString().toLowerCase(), contains('usage'));
    });
  });
}

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
