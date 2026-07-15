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

import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:wger/core/consts.dart';

/// Persists the user-defined custom request headers (e.g. Cloudflare Access
/// service tokens) that must accompany every request to a self-hosted server.
///
/// These are potentially secret (a service-token secret is a credential), so
/// they live in platform-level secure storage next to the refresh token rather
/// than in shared preferences. Wrapped behind an interface so tests can swap in
/// an in-memory fake without touching platform channels.
abstract interface class CustomHeadersStorage {
  /// Returns the persisted header map, or an empty map when none is stored.
  Future<Map<String, String>> read();

  /// Persists [headers], replacing any previous value. An empty map removes
  /// the stored entry entirely.
  Future<void> write(Map<String, String> headers);

  /// Removes any persisted headers. No-op when none are stored.
  Future<void> clear();
}

class FlutterCustomHeadersStorage implements CustomHeadersStorage {
  final FlutterSecureStorage _storage;
  final _logger = Logger('CustomHeadersStorage');

  FlutterCustomHeadersStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<Map<String, String>> read() async {
    try {
      final raw = await _storage.read(key: SECURE_STORAGE_CUSTOM_HEADERS);
      if (raw == null || raw.isEmpty) {
        return {};
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return {};
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (e, s) {
      // A locked/unavailable keyring (or a test environment without the secure
      // storage plugin) must not abort the auth flow: the headers are simply
      // treated as absent, mirroring the best-effort refresh-token handling.
      _logger.warning('Could not read custom headers, treating as none', e, s);
      return {};
    }
  }

  @override
  Future<void> write(Map<String, String> headers) async {
    if (headers.isEmpty) {
      await clear();
      return;
    }
    try {
      await _storage.write(
        key: SECURE_STORAGE_CUSTOM_HEADERS,
        value: json.encode(headers),
      );
    } catch (e, s) {
      _logger.warning('Could not persist custom headers', e, s);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: SECURE_STORAGE_CUSTOM_HEADERS);
    } catch (e, s) {
      _logger.warning('Could not clear custom headers', e, s);
    }
  }
}

final customHeadersStorageProvider = Provider<CustomHeadersStorage>(
  (ref) => FlutterCustomHeadersStorage(),
);

/// In-memory snapshot of the active custom headers.
///
/// The HTTP client injects these synchronously on every outgoing request, so
/// the current value must be readable without awaiting secure storage. The
/// auth notifier owns the lifecycle: it loads the persisted headers into the
/// holder on startup, sets them from the login form before authenticating, and
/// clears them on logout.
class CustomHeadersHolder {
  Map<String, String> _headers = const {};

  /// The headers currently applied to outgoing requests.
  Map<String, String> get headers => _headers;

  /// Replaces the active headers. A copy is stored so later mutations of the
  /// passed-in map don't leak into live requests.
  void set(Map<String, String> headers) {
    _headers = Map.unmodifiable(headers);
  }
}

final customHeadersHolderProvider = Provider<CustomHeadersHolder>(
  (ref) => CustomHeadersHolder(),
);

/// HTTP client wrapper that adds the user-defined custom headers to every
/// outgoing request. Uses `putIfAbsent` so it never clobbers headers the app
/// itself sets (`Authorization`, `Content-Type`, ...); custom headers carry
/// distinct names (e.g. `CF-Access-Client-Id`).
///
/// Reads the current headers through a callback rather than capturing a map so
/// updates made after the client is constructed (login, logout) take effect
/// immediately.
class CustomHeadersHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> Function() _read;

  CustomHeadersHttpClient({
    required http.Client inner,
    required Map<String, String> Function() read,
  }) : _inner = inner,
       _read = read;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    for (final entry in _read().entries) {
      request.headers.putIfAbsent(entry.key, () => entry.value);
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
