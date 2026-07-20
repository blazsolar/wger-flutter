/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2026 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Debug-only HTTP client wrapper that traces every outgoing request: its
/// method, full URL, the exact headers as sent (so custom headers and the
/// `Authorization` value are visible), and the response status. Error
/// responses (>= 400) also log a snippet of the body, which surfaces e.g. a
/// reverse-proxy / Cloudflare block page returned for a path the WAF doesn't
/// allow.
///
/// Wire it as the *innermost* client (closest to the real `http.Client`) so
/// every header the outer wrappers add (`AuthHttpClient`'s `Authorization`,
/// `CustomHeadersHttpClient`'s custom headers) is already on the request by
/// the time it is logged.
///
/// WARNING: the logged headers include bearer tokens and any secret custom
/// headers, so this is intentionally only enabled in debug builds (see the
/// wiring in `authHttpClientProvider`). Do not enable it in a release build.
class LoggingHttpClient extends http.BaseClient {
  final http.Client _inner;
  final _logger = Logger('HttpTrace');

  LoggingHttpClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final line = StringBuffer('→ ${request.method} ${request.url}');
    for (final entry in request.headers.entries) {
      line.write('\n    ${entry.key}: ${entry.value}');
    }
    _logger.info(line.toString());

    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e) {
      _logger.info('✗ ${request.method} ${request.url} — $e');
      rethrow;
    }

    // Buffer the body so it can be logged and still handed to the caller as a
    // fresh stream. Safe here: every request routed through this client returns
    // a small JSON / error payload (the PowerSync streaming socket and media
    // downloads do not go through this client).
    final bytes = await response.stream.toBytes();
    if (response.statusCode >= 400) {
      final body = utf8.decode(bytes, allowMalformed: true);
      final snippet = body.substring(0, math.min(500, body.length));
      _logger.info(
        '← ${response.statusCode} ${request.method} ${request.url}\n    $snippet',
      );
    } else {
      _logger.info('← ${response.statusCode} ${request.method} ${request.url}');
    }

    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
