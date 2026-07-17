/// Single source of truth for the CLI package version.
///
/// A compiled binary carries no pubspec, so the version must live
/// in a Dart constant. Kept in lock-step with `cli/pubspec.yaml`
/// by `test/version_test.dart` — bump both together.
///
/// Author: Paul Snow
/// Since: 0.0.2
library;

/// The CLI package version, mirrored from `cli/pubspec.yaml`.
const String cliVersion = '0.0.2';
