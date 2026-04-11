/// Hand-rolled argument-parsing helpers for the `dart-accuraterip`
/// CLI.
///
/// Deliberately minimal — only what the four subcommands need:
///
///  - [parseBooleanFlag] strips a `--flag` from a list in place and
///    returns whether it was present.
///  - [requirePositional], [requireAtLeastOnePositional], and
///    [requireExactlyNPositionals] assert positional-count
///    expectations and throw a descriptive [FormatException] on
///    failure.
///  - [isHelp] detects `--help` / `-h` anywhere in the list.
///  - [rejectUnknownFlags] throws if any dash-prefixed token
///    remains after all known flags have been stripped, catching
///    typos like `--frist`.
///
/// A fuller argument parser (`package:args`) would be more polished
/// but adds a runtime dependency, which this CLI deliberately
/// avoids. Four subcommands with at most two flags each fit
/// comfortably in ~80 lines of hand-rolled code.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

/// Strip every occurrence of [flag] from [args] and return whether
/// it was present at least once.
bool parseBooleanFlag(List<String> args, String flag) {
  var found = false;
  args.removeWhere((a) {
    if (a == flag) {
      found = true;
      return true;
    }
    return false;
  });
  return found;
}

/// Assert that [args] contains exactly one positional argument,
/// returning it. The [subcommand] and [usageFragment] are used to
/// build a helpful error message when the assertion fails.
String requirePositional(
  List<String> args,
  String subcommand,
  String usageFragment,
) {
  if (args.length != 1) {
    throw FormatException(
      'usage: dart-accuraterip $subcommand $usageFragment',
    );
  }
  return args.single;
}

/// Assert that [args] is non-empty, returning it unchanged.
List<String> requireAtLeastOnePositional(
  List<String> args,
  String subcommand,
  String usageFragment,
) {
  if (args.isEmpty) {
    throw FormatException(
      'usage: dart-accuraterip $subcommand $usageFragment',
    );
  }
  return args;
}

/// Assert that [args] contains exactly [n] positional arguments,
/// returning them unchanged.
List<String> requireExactlyNPositionals(
  List<String> args,
  int n,
  String subcommand,
  String usageFragment,
) {
  if (args.length != n) {
    throw FormatException(
      'usage: dart-accuraterip $subcommand $usageFragment',
    );
  }
  return args;
}

/// Return `true` if any token in [args] is `--help` or `-h`.
///
/// Callers use this before any other parsing so that
/// `dart-accuraterip crc --help` prints crc's usage even if the
/// positional-count assertions would otherwise reject it.
bool isHelp(List<String> args) => args.any((a) => a == '--help' || a == '-h');

/// Throw a [FormatException] if any dash-prefixed token remains in
/// [args]. Call this after stripping all known flags — anything
/// still starting with `-` is a typo or an unsupported option.
void rejectUnknownFlags(List<String> args) {
  for (final a in args) {
    if (a.startsWith('-')) {
      throw FormatException('unknown flag: $a');
    }
  }
}
