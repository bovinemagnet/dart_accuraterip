// dart-accuraterip — command-line interface for dart_accuraterip.
//
// Dispatches the subcommand in argv[0] to one of four command
// functions defined under lib/src/commands/. Any FormatException
// thrown by a command is caught, printed to stderr, and mapped to
// exit code 64 (EX_USAGE). Other exceptions escape to the Dart
// runtime so they show a useful stack trace.
//
// Author: Paul Snow
// Since: 0.0.1

import 'dart:io';

import 'package:dart_accuraterip_cli/src/commands/crc.dart';
import 'package:dart_accuraterip_cli/src/commands/disc_id.dart';
import 'package:dart_accuraterip_cli/src/commands/query.dart';
import 'package:dart_accuraterip_cli/src/commands/verify.dart';

/// The package version — kept in sync with cli/pubspec.yaml.
const String cliVersion = '0.0.1';

const String _rootUsage = '''
dart-accuraterip $cliVersion — AccurateRip CRC, disc ID, and
database lookup for WAV rips.

usage:
  dart-accuraterip --help
  dart-accuraterip --version
  dart-accuraterip <command> [args...]

commands:
  crc       compute v1 and v2 CRCs for a single WAV file
  disc-id   compute a disc ID from a list of WAV files
  verify    end-to-end verification of a rip against the database
  query     fetch and pretty-print a raw database response

Run `dart-accuraterip <command> --help` for per-command usage.
''';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
    stdout.writeln(_rootUsage);
    return;
  }
  if (argv.first == '--version') {
    stdout.writeln('dart-accuraterip $cliVersion');
    return;
  }

  final subcommand = argv.first;
  final rest = argv.sublist(1);

  final code = switch (subcommand) {
    'crc' => await runCrc(rest, stdout),
    'disc-id' => await runDiscId(rest, stdout),
    'verify' => await runVerify(rest, stdout),
    'query' => await runQuery(rest, stdout),
    _ => _unknownCommand(subcommand),
  };

  exitCode = code;
}

int _unknownCommand(String name) {
  stderr.writeln('dart-accuraterip: unknown command: $name');
  stderr.writeln();
  stderr.writeln(_rootUsage);
  return 64;
}
