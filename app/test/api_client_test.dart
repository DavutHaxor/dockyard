import 'dart:convert';

import 'package:dockyard/core/config/settings.dart';
import 'package:dockyard/core/models/container.dart';
import 'package:dockyard/core/network/api_client.dart';
import 'package:dockyard/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = '0123456789abcdef0123456789abcdef';

DockyardSettings _settings({String url = 'http://daemon.test:8080'}) =>
    DockyardSettings(serverUrl: url, adminToken: _token);

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('exchanges the admin token and lists containers', () async {
    final requests = <http.Request>[];
    final mock = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v1/auth/login') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'token': _token});
        return _json({
          'token': 'jwt-1',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }, 200);
      }
      if (request.url.path == '/api/v1/containers') {
        expect(request.headers['Authorization'], 'Bearer jwt-1');
        return _json({
          'containers': [
            {
              'id': 'abc',
              'name': 'traefik',
              'image': 'traefik:v3',
              'state': 'running',
              'status': 'Up 1 hour',
              'created': 1710000000,
              'ports': <Object>[],
            },
          ],
        }, 200);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final api = ApiClient(settings: _settings(), httpClient: mock);
    addTearDown(api.close);

    final containers = await api.listContainers();
    expect(containers, hasLength(1));
    expect(containers.single.name, 'traefik');
    expect(requests, hasLength(2));
  });

  test('re-authenticates once after a 401', () async {
    var logins = 0;
    var containerCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        logins++;
        return _json({
          'token': 'jwt-$logins',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }, 200);
      }
      if (request.url.path == '/api/v1/containers') {
        containerCalls++;
        if (containerCalls == 1) {
          return _json({
            'error': {'code': 'unauthorized', 'message': 'expired'},
          }, 401);
        }
        expect(request.headers['Authorization'], 'Bearer jwt-2');
        return _json({'containers': <Object>[]}, 200);
      }
      fail('Unexpected request: ${request.url}');
    });

    final api = ApiClient(settings: _settings(), httpClient: mock);
    addTearDown(api.close);

    expect(await api.listContainers(), isEmpty);
    expect(logins, 2);
    expect(containerCalls, 2);
  });

  test('surfaces daemon error messages', () async {
    final mock = MockClient(
      (_) async => _json({
        'error': {'code': 'unauthorized', 'message': 'invalid admin token'},
      }, 401),
    );
    final api = ApiClient(settings: _settings(), httpClient: mock);
    addTearDown(api.close);

    await expectLater(
      api.listContainers(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.message, 'message', 'invalid admin token')
            .having((error) => error.code, 'code', 'unauthorized')
            .having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('returns null when no metric sample exists yet', () async {
    final mock = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _json({
          'token': 'jwt',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }, 200);
      }
      return _json({
        'error': {'code': 'metrics_unavailable', 'message': 'not ready'},
      }, 503);
    });
    final api = ApiClient(settings: _settings(), httpClient: mock);
    addTearDown(api.close);

    expect(await api.latestMetrics(), isNull);
  });

  test('posts container actions with the encoded identifier', () async {
    String? actionPath;
    final mock = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _json({
          'token': 'jwt',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }, 200);
      }
      actionPath = request.url.path;
      return _json({'status': 'ok'}, 200);
    });
    final api = ApiClient(settings: _settings(), httpClient: mock);
    addTearDown(api.close);

    await api.containerAction('a b', ContainerAction.start);
    expect(actionPath, '/api/v1/containers/a%20b/start');
  });

  test('builds WebSocket URIs for http and https with path prefixes', () {
    final httpApi = ApiClient(
      settings: _settings(url: 'http://daemon.test:8080/dockyard/'),
    );
    addTearDown(httpApi.close);
    expect(
      httpApi.webSocketUri('abc'),
      Uri.parse('ws://daemon.test:8080/dockyard/api/v1/ws?token=abc'),
    );

    final httpsApi = ApiClient(
      settings: _settings(url: 'https://daemon.test:8443/dockyard'),
    );
    addTearDown(httpsApi.close);
    expect(
      httpsApi.webSocketUri('abc'),
      Uri.parse('wss://daemon.test:8443/dockyard/api/v1/ws?token=abc'),
    );
  });
}
