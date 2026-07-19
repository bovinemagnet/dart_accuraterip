# Repository Guidelines

## Project Structure & Module Organization

- `lib/dart_accuraterip.dart` is the public library entry point.
- `lib/src/` contains implementation modules for CRCs, disc IDs, protocol models, WAV parsing, and IO clients.
- `test/` contains unit, golden, protocol, client, WAV, and CRC differential tests. Fixtures live in `test/fixtures/`.
- `example/` holds runnable library examples. The root analyzer excludes this directory.
- `cli/` is a separate Dart package with its own `pubspec.yaml`, `analysis_options.yaml`, `bin/`, `lib/src/`, and `test/`.
- `benchmark/` and `tool/` contain developer-only performance and verification utilities.

## Build, Test, and Development Commands

Run package commands from the directory that owns the relevant `pubspec.yaml`.

- `dart pub get` installs package dependencies.
- `dart format --output=none --set-exit-if-changed .` checks repository formatting, matching CI.
- `dart analyze --fatal-warnings` runs static analysis for the current package.
- `dart test` runs the current package test suite.
- `cd cli && dart pub get && dart analyze --fatal-warnings && dart test` validates the CLI package.
- `dart doc --dry-run` checks generated API documentation.
- `dart run tool/verify_disc.dart --flac-dir <path>` performs optional real-disc verification and requires external audio tooling.

## Coding Style & Naming Conventions

Use Dart SDK defaults: two-space indentation, `dart format`, and `package:lints/recommended.yaml`. Prefer focused modules under `lib/src/` and expose stable APIs through `lib/dart_accuraterip.dart`. Use Dart naming conventions: `lowerCamelCase` for functions and variables, `UpperCamelCase` for types, and `snake_case.dart` for files. Keep CLI internals dependency-light; the CLI intentionally avoids packages such as `args` and `http`.

## Testing Guidelines

Tests use `package:test`. Name files with the `_test.dart` suffix and keep fixtures under `test/fixtures/`. Add focused coverage for CRC arithmetic, binary protocol parsing, URL construction, client behavior, WAV loading, and CLI command parsing when touching those areas. Run both root and `cli/` test suites before opening a PR.

## Commit & Pull Request Guidelines

Recent commits use short, imperative summaries such as `Add benchmark/ directory for CRC throughput on Dart VM` and `CI: run cli pub get before root analyse`. Keep subjects concise, mention affected areas when useful, and reference issues with `closes #N`. PRs should describe behavior changes, list validation commands, link issues, and note protocol, fixture, or platform impacts.

## Agent-Specific Instructions

Do not edit generated or cache directories such as `.dart_tool/`. Treat `cli/` as an independent package during analysis and testing. Preserve GPL-3.0 licensing and fixture provenance notes when moving or modifying test data.
