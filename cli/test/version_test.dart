// Drift guard for the CLI version constant.
//
// `cliVersion` in lib/src/version.dart is the single source of
// truth used by both `--version` output and the HTTP User-Agent.
// It cannot be read from pubspec.yaml at runtime (a compiled
// binary carries no pubspec), so this test pins the hand-synced
// pair: bump `version:` in cli/pubspec.yaml and `cliVersion`
// together, or this fails.

import 'dart:io';

import 'package:dart_accuraterip_cli/src/io_fetcher.dart';
import 'package:dart_accuraterip_cli/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('cliVersion matches the version in cli/pubspec.yaml', () {
    // `dart test` runs with the package root as the working
    // directory, so pubspec.yaml resolves relative to cli/.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'no version: line in cli/pubspec.yaml');
    expect(cliVersion, equals(match!.group(1)));
  });

  test('cliUserAgent embeds cliVersion', () {
    expect(cliUserAgent, equals('dart-accuraterip/$cliVersion'));
  });
}
