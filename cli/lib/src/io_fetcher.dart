/// A minimal `dart:io`-backed AccurateRipFetcher for the CLI.
///
/// The library is transport-agnostic — it exposes the
/// `AccurateRipFetcher` typedef
/// `Future<Uint8List> Function(Uri url)`. The CLI just needs ONE
/// network call (`GET` the database `.bin`), so we use
/// `dart:io`'s built-in `HttpClient` directly rather than pull in
/// `package:http`. `dart:io` is part of the SDK — zero runtime
/// dependency cost.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_accuraterip/dart_accuraterip.dart';

/// User-Agent header used when hitting accuraterip.com. Bumped in
/// lock-step with the CLI package version — see
/// `bin/dart_accuraterip.dart`.
const String cliUserAgent = 'dart-accuraterip/0.0.1';

/// Default connect + response timeout for the single AR database
/// lookup.
const Duration fetchTimeout = Duration(seconds: 10);

/// An [AccurateRipFetcher] implementation that uses `dart:io`'s
/// built-in [HttpClient].
///
/// Behaviour:
///
///  - Returns the response body as a [Uint8List] on HTTP 200.
///  - Returns `Uint8List(0)` on HTTP 404, which
///    [AccurateRipClient.queryDisc] treats as a cache miss and
///    translates to `null` without throwing.
///  - Throws [HttpException] on any other non-200 status.
///  - Propagates timeouts and network errors as exceptions.
Future<Uint8List> ioFetcher(Uri url) async {
  final client = HttpClient()..connectionTimeout = fetchTimeout;
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, cliUserAgent);
    final response = await request.close().timeout(fetchTimeout);
    if (response.statusCode == 404) {
      // Drain the body so the socket can be returned to the pool.
      await response.drain<void>();
      return Uint8List(0);
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.toBytes();
  } finally {
    client.close(force: true);
  }
}
