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

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wger/core/network/custom_headers.dart';

void main() {
  group('CustomHeadersHolder', () {
    test('starts empty', () {
      expect(CustomHeadersHolder().headers, isEmpty);
    });

    test('set stores an immutable copy that is decoupled from the source', () {
      final holder = CustomHeadersHolder();
      final source = {'CF-Access-Client-Id': 'id'};
      holder.set(source);

      // Mutating the source after set must not leak into the live headers.
      source['CF-Access-Client-Id'] = 'changed';
      expect(holder.headers['CF-Access-Client-Id'], 'id');

      // The exposed map is unmodifiable.
      expect(() => holder.headers['x'] = 'y', throwsUnsupportedError);
    });
  });

  group('CustomHeadersHttpClient', () {
    Future<Map<String, String>> capture(
      Map<String, String> custom, {
      Map<String, String>? requestHeaders,
    }) async {
      late Map<String, String> seen;
      final inner = MockClient((request) async {
        seen = request.headers;
        return http.Response('', 200);
      });
      final client = CustomHeadersHttpClient(inner: inner, read: () => custom);
      await client.get(Uri.parse('https://self.hosted/api'), headers: requestHeaders);
      return seen;
    }

    test('adds the custom headers to the outgoing request', () async {
      final headers = await capture({
        'CF-Access-Client-Id': 'the-id',
        'CF-Access-Client-Secret': 'the-secret',
      });
      expect(headers['CF-Access-Client-Id'], 'the-id');
      expect(headers['CF-Access-Client-Secret'], 'the-secret');
    });

    test('sends nothing extra when there are no custom headers', () async {
      final headers = await capture(const {});
      expect(headers.containsKey('CF-Access-Client-Id'), isFalse);
    });

    test('does not clobber a header the caller already set', () async {
      final headers = await capture(
        {'Authorization': 'Bearer custom'},
        requestHeaders: {'Authorization': 'Bearer real'},
      );
      expect(headers['authorization'], 'Bearer real');
    });

    test('reads the callback on every send so later updates take effect', () async {
      var custom = <String, String>{};
      final inner = MockClient((request) async {
        return http.Response(request.headers['X-Token'] ?? 'none', 200);
      });
      final client = CustomHeadersHttpClient(inner: inner, read: () => custom);

      final before = await client.get(Uri.parse('https://self.hosted/'));
      expect(before.body, 'none');

      custom = {'X-Token': 'set'};
      final after = await client.get(Uri.parse('https://self.hosted/'));
      expect(after.body, 'set');
    });
  });
}
