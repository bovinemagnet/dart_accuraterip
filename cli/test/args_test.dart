// Unit tests for the hand-rolled argument parser in
// cli/lib/src/args.dart.
//
// The parser intentionally supports only what the four
// subcommands need: positional arguments, a handful of boolean
// flags, and --help detection at the subcommand level. Anything
// more exotic would be a reason to reach for package:args, which
// this release deliberately avoids.

import 'package:dart_accuraterip_cli/src/args.dart';
import 'package:test/test.dart';

void main() {
  group('parseBooleanFlag', () {
    test('returns true when the flag is present and strips it', () {
      final args = <String>['--first', 'track.wav'];

      final hasFirst = parseBooleanFlag(args, '--first');

      expect(hasFirst, isTrue);
      expect(args, equals(['track.wav']));
    });

    test('returns false and leaves positional args untouched when absent', () {
      final args = <String>['track.wav'];

      final hasFirst = parseBooleanFlag(args, '--first');

      expect(hasFirst, isFalse);
      expect(args, equals(['track.wav']));
    });

    test('strips every occurrence of the flag', () {
      final args = <String>['--first', 'track.wav', '--first'];

      expect(parseBooleanFlag(args, '--first'), isTrue);
      expect(args, equals(['track.wav']));
    });
  });

  group('requirePositional', () {
    test('returns the argument when exactly one is present', () {
      expect(
        requirePositional(['track.wav'], 'crc', '<file.wav>'),
        equals('track.wav'),
      );
    });

    test('throws FormatException when no positional is present', () {
      expect(
        () => requirePositional([], 'crc', '<file.wav>'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('crc'),
          ),
        ),
      );
    });

    test('throws FormatException when more than one positional is present', () {
      expect(
        () => requirePositional(
          ['a.wav', 'b.wav'],
          'crc',
          '<file.wav>',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('requireAtLeastOnePositional', () {
    test('returns the list unchanged when non-empty', () {
      expect(
        requireAtLeastOnePositional(
          ['a.wav', 'b.wav'],
          'disc-id',
          '<file.wav> ...',
        ),
        equals(['a.wav', 'b.wav']),
      );
    });

    test('throws FormatException when empty', () {
      expect(
        () => requireAtLeastOnePositional(
          [],
          'disc-id',
          '<file.wav> ...',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('requireExactlyNPositionals', () {
    test('returns the list unchanged when the count matches', () {
      expect(
        requireExactlyNPositionals(
          ['a', 'b', 'c', 'd'],
          4,
          'query',
          '<discId1> <discId2> <cddb> <trackCount>',
        ),
        equals(['a', 'b', 'c', 'd']),
      );
    });

    test('throws FormatException when too few', () {
      expect(
        () => requireExactlyNPositionals(
          ['a'],
          4,
          'query',
          '<...>',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when too many', () {
      expect(
        () => requireExactlyNPositionals(
          ['a', 'b', 'c', 'd', 'e'],
          4,
          'query',
          '<...>',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('isHelp', () {
    test('detects --help and -h anywhere in the list', () {
      expect(isHelp(['--help']), isTrue);
      expect(isHelp(['-h']), isTrue);
      expect(isHelp(['foo', '--help', 'bar']), isTrue);
      expect(isHelp(['foo', 'bar']), isFalse);
      expect(isHelp([]), isFalse);
    });
  });

  group('rejectUnknownFlags', () {
    test('passes when every entry is a positional', () {
      expect(
        () => rejectUnknownFlags(['a.wav', 'b.wav']),
        returnsNormally,
      );
    });

    test('throws when a dash-prefixed token remains after flag parsing', () {
      expect(
        () => rejectUnknownFlags(['a.wav', '--bogus']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
