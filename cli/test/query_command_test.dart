// Integration tests for the `query` subcommand.
//
// Covers both the argument-parsing rejections and the command's own
// output: the success path (stubbed fetcher → pretty-printed
// pressings) and the not-found path. The verify command shares the
// fetcher plumbing but formats its output differently, so query's
// own printing loop needs its own coverage.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip_cli/src/commands/query.dart';
import 'package:test/test.dart';

void main() {
  group('runQuery', () {
    test('rejects a disc ID that does not fit in 32 bits', () async {
      final buffer = StringBuffer();
      // 0x1FFFFFFFF is a syntactically valid hex literal but
      // overflows 32 bits — buildAccurateRipUrl would otherwise
      // produce a 9-character hex segment and mis-index the
      // directory components.
      final exit = await runQuery(
        ['1FFFFFFFF', '00000002', '00000003', '5'],
        _bufferSink(buffer),
        fetcher: (uri) async => Uint8List(0),
      );
      expect(exit, equals(64));
    });

    test('rejects a non-positive track count', () async {
      final buffer = StringBuffer();
      final exit = await runQuery(
        ['1', '2', '3', '0'],
        _bufferSink(buffer),
        fetcher: (uri) async => Uint8List(0),
      );
      expect(exit, equals(64));
    });

    test('--help returns zero and prints usage', () async {
      final buffer = StringBuffer();
      final exit = await runQuery(
        ['--help'],
        _bufferSink(buffer),
        fetcher: (uri) async => Uint8List(0),
      );
      expect(exit, equals(0));
      expect(buffer.toString().toLowerCase(), contains('usage'));
    });

    test('pretty-prints each track and pressing on the success path', () async {
      final buffer = StringBuffer();
      final response = _buildChunk(
        discId1: 0x0000f21c,
        discId2: 0x00027ef8,
        cddbDiscId: 0x05021002,
        tracks: const [
          (confidence: 5, crc: 0xdeadbeef, frame450Crc: 0x00000000),
          (confidence: 42, crc: 0xcafebabe, frame450Crc: 0x12345678),
        ],
      );

      final exit = await runQuery(
        ['0000f21c', '00027ef8', '05021002', '2'],
        _bufferSink(buffer),
        fetcher: (uri) async => response,
      );

      final out = buffer.toString();
      expect(exit, equals(0));
      // The lookup URL echoes the disc ID (three-nibble path of
      // discId1 = 0x0000f21c → c/1/2).
      expect(out, contains('Querying:'));
      expect(out, contains('/c/1/2/'));
      // Track 1: confidence padded to width 3, CRCs as 8 hex digits.
      expect(out, contains('Track 01: 1 pressing(s)'));
      expect(out, contains('confidence=  5'));
      expect(out, contains('crc=0xdeadbeef'));
      expect(out, contains('frame450Crc=0x00000000'));
      // Track 2.
      expect(out, contains('Track 02: 1 pressing(s)'));
      expect(out, contains('confidence= 42'));
      expect(out, contains('crc=0xcafebabe'));
      expect(out, contains('frame450Crc=0x12345678'));
    });

    test('reports a miss and exits 1 when the disc is not in the database',
        () async {
      final buffer = StringBuffer();
      final exit = await runQuery(
        ['0000f21c', '00027ef8', '05021002', '2'],
        _bufferSink(buffer),
        // An empty body is what the client collapses to a null result.
        fetcher: (uri) async => Uint8List(0),
      );
      expect(exit, equals(1));
      expect(buffer.toString(), contains('No entry in the AccurateRip'));
    });
  });
}

/// Build a single AccurateRip response chunk as bytes. Mirrors the
/// wire format exercised by the root package's protocol tests:
/// `trackCount:u8, discId1/discId2/cddbDiscId:u32 LE, then
/// (confidence:u8, crc:u32 LE, frame450Crc:u32 LE) per track`.
Uint8List _buildChunk({
  required int discId1,
  required int discId2,
  required int cddbDiscId,
  required List<({int confidence, int crc, int frame450Crc})> tracks,
}) {
  final builder = BytesBuilder();
  builder.addByte(tracks.length);
  builder.add(_uint32LE(discId1));
  builder.add(_uint32LE(discId2));
  builder.add(_uint32LE(cddbDiscId));
  for (final t in tracks) {
    builder.addByte(t.confidence);
    builder.add(_uint32LE(t.crc));
    builder.add(_uint32LE(t.frame450Crc));
  }
  return builder.toBytes();
}

List<int> _uint32LE(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

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
