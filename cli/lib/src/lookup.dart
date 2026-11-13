/// AccurateRip database lookup for the CLI, keeping "the disc is not
/// in the database" apart from "the database could not be asked".
///
/// The library's `AccurateRipClient.queryDisc` deliberately collapses
/// every failure to `null`. That is the right contract for a
/// convenience client, but in a CLI that gates pipelines on its exit
/// status it turns "offline" into "unknown disc". This helper drives
/// the lower-level `buildAccurateRipUrl` / `parseAccurateRipResponse`
/// pair directly, as the client's documentation recommends for
/// callers that need the distinction.
///
/// Author: Paul Snow
/// Since: 0.0.0
library;

import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';

/// Exit status when the database lookup itself failed — network
/// error, timeout, unexpected HTTP status, or an unparseable body.
/// `EX_UNAVAILABLE` from `sysexits.h`, alongside the CLI's existing
/// `EX_USAGE` (64).
const int exitLookupFailed = 69;

/// Thrown by [lookupDisc] when the database could not be queried or
/// returned something that is not an AccurateRip response.
class LookupFailedException implements Exception {
  /// Create a [LookupFailedException] with a human-readable [message].
  const LookupFailedException(this.message);

  /// Description of what went wrong, suitable for stderr.
  final String message;

  @override
  String toString() => 'LookupFailedException: $message';
}

/// Look up [id] through [fetch].
///
/// Returns the parsed result, or `null` when the disc is not in the
/// database (the fetcher returned an empty body, which is how a
/// `404 Not Found` is reported). Throws [LookupFailedException] if
/// the fetcher throws or the body cannot be parsed.
Future<AccurateRipDiscResult?> lookupDisc(
  AccurateRipDiscId id,
  AccurateRipFetcher fetch,
) async {
  final Uint8List bytes;
  try {
    bytes = await fetch(buildAccurateRipUrl(id));
  } catch (e) {
    throw LookupFailedException('database lookup failed: $e');
  }
  if (bytes.isEmpty) return null;
  final result = parseAccurateRipResponse(bytes);
  if (result == null) {
    throw LookupFailedException(
      'database lookup failed: response (${bytes.length} bytes) is not '
      'an AccurateRip response',
    );
  }
  return result;
}
