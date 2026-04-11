/// HTTP client convenience wrapper for the AccurateRip database.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:typed_data';

import '../accuraterip_disc_id.dart';
import '../accuraterip_models.dart';
import '../accuraterip_protocol.dart';

/// Function signature for fetching the raw bytes of an HTTP GET
/// request to the AccurateRip database.
///
/// Consumers supply their own HTTP implementation — `package:http`,
/// `package:dio`, a Flutter `Client`, a mock, anything. The
/// package itself has no HTTP dependency.
///
/// The fetcher should either:
///  - return the response body as a [Uint8List] on any successful
///    status, or
///  - throw on transport failures, or
///  - return an empty [Uint8List] (or throw) on `404 Not Found`,
///    which [AccurateRipClient.queryDisc] treats as a cache miss
///    and translates into `null`.
typedef AccurateRipFetcher = Future<Uint8List> Function(Uri url);

/// Convenience client that fetches an AccurateRip response, decodes
/// it, and returns an [AccurateRipDiscResult].
///
/// Use this when you want a one-call lookup; drop down to the
/// lower-level [buildAccurateRipUrl] and [parseAccurateRipResponse]
/// functions if you need to customise caching, retries, or
/// response-body handling.
class AccurateRipClient {
  /// Create an [AccurateRipClient] backed by [fetch].
  const AccurateRipClient({required this.fetch});

  /// The injected HTTP fetcher. See [AccurateRipFetcher].
  final AccurateRipFetcher fetch;

  /// Look up [id] in the AccurateRip database.
  ///
  /// Returns the parsed [AccurateRipDiscResult] on success, or
  /// `null` when:
  ///  - the fetcher returns an empty response body,
  ///  - the response body cannot be parsed as a valid AccurateRip
  ///    chunk stream,
  ///  - the fetcher throws (e.g. HTTP 404, network failure, DNS
  ///    failure).
  ///
  /// Callers that want to distinguish transport failures from
  /// empty responses should invoke [buildAccurateRipUrl] and their
  /// own HTTP layer directly rather than going through this
  /// wrapper.
  Future<AccurateRipDiscResult?> queryDisc(AccurateRipDiscId id) async {
    final url = buildAccurateRipUrl(id);
    try {
      final bytes = await fetch(url);
      if (bytes.isEmpty) return null;
      return parseAccurateRipResponse(bytes);
    } catch (_) {
      return null;
    }
  }
}
