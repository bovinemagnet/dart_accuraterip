#!/usr/bin/env bash
# Publish dart_accuraterip_cli from a clean export.
#
# Why not `cd cli && dart pub publish`? The repository root's
# .pubignore contains a `cli/` pattern (to keep the cli out of the
# LIBRARY tarball), and pub applies parent-directory ignore files
# when publishing a sub-directory package — hiding every cli file
# and failing with "The pubspec is hidden". Exporting to a
# directory outside the repo sidesteps that, and dropping
# pubspec_overrides.yaml from the export means the dry-run
# resolves dart_accuraterip from pub.dev exactly as consumers
# will.
#
# Usage:
#   tool/publish_cli.sh            # dry-run (safe default)
#   tool/publish_cli.sh --publish  # the real thing (interactive)
#
# Author: Paul Snow
# Since: 0.0.4 (cli)

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export_dir="$(mktemp -d)/dart_accuraterip_cli"
trap 'rm -rf "$(dirname "$export_dir")"' EXIT

mkdir -p "$export_dir"
# Everything except build output and the dev-only path override.
rsync -a \
  --exclude '.dart_tool/' \
  --exclude 'pubspec_overrides.yaml' \
  --exclude 'pubspec.lock' \
  "$repo_root/cli/" "$export_dir/"

cd "$export_dir"
dart pub get
dart analyze --fatal-warnings
dart test

if [[ "${1:-}" == "--publish" ]]; then
  dart pub publish
else
  dart pub publish --dry-run
fi
