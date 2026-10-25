import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/settings.dart';
import '../models/container.dart';
import '../models/metrics_sample.dart';
import 'api_exception.dart';

/// Typed REST client for the Dockyard daemon.
///
/// The app stores the admin token, not a session. This client exchanges it for
/// a short-lived JWT on demand and retries once if the session expires.
class ApiClient {
  ApiClient({
    required this.settings,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final DockyardSettings settings;
  final Duration timeout;
  final http.Client _http;

  String? _sessionToken;
  DateTime? _sessionExpiresAt;

  /// Authenticates against the configured daemon. Used by Settings to verify
  /// the URL and token without saving them first.
  Future<void> testConnection() async {
    _clearSession();
    await sessionToken();
  }

  /// Returns a valid session JWT, logging in again when needed.
  Future<String> sessionToken() async {
    final expiresAt = _sessionExpiresAt;
    if (_sessionToken != null &&
        expiresAt != null &&
        expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(seconds: 30)),
        )) {
      return _sessionToken!;
    }

    if (settings.adminToken.trim().isEmpty) {
      throw const ApiException('Add your admin token in Settings.');
    }

    final response = await _perform(
      () => _http.post(
        _uri('/api/v1/auth/login'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': settings.adminToken.trim()}),
      ),
    );
    if (response.statusCode != 200) {
      throw _errorFrom(response);
    }

    final body = _decodeMap(response);
    final token = body['token'];
    final parsedExpiry = DateTime.tryParse(
      body['expires_at']?.toString() ?? '',
    );
    if (token is! String || token.isEmpty) {
      throw const ApiException('The daemon returned an invalid session.');
    }

    _sessionToken = token;
    _sessionExpiresAt = parsedExpiry?.toUtc();
    return token;
  }

  Future<List<DockerContainer>> listContainers() async {
    final body = await _getJson('/api/v1/containers');
    final raw = body['containers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DockerContainer.fromJson)
        .toList(growable: false);
  }

  Future<MetricsSample?> latestMetrics() async {
    final response = await _authorized(
      (token) => _http.get(_uri('/api/v1/metrics'), headers: _headers(token)),
    );
    if (response.statusCode == 503) return null;
    _ensureSuccess(response);
    return MetricsSample.fromJson(_decodeMap(response));
  }

  Future<List<MetricsSample>> metricsHistory({int limit = 0}) async {
    final body = await _getJson(
      '/api/v1/metrics/history',
      query: limit > 0 ? {'limit': '$limit'} : null,
    );
    final raw = body['samples'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MetricsSample.fromJson)
        .toList(growable: false);
  }

  Future<void> containerAction(String id, ContainerAction action) async {
    final response = await _authorized(
      (token) => _http.post(
        _uri(
          '/api/v1/containers/${Uri.encodeComponent(id)}/${action.wireName}',
        ),
        headers: _headers(token),
      ),
    );
    _ensureSuccess(response);
  }

  /// WebSocket URL with the session token as a query parameter. The daemon
  /// accepts this form because browser clients cannot set upgrade headers.
  Uri webSocketUri(String token) {
    final httpUri = _uri('/api/v1/ws', query: {'token': token});
    return httpUri.replace(scheme: httpUri.scheme == 'https' ? 'wss' : 'ws');
  }

  void close() => _http.close();

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _authorized(
      (token) => _http.get(_uri(path, query: query), headers: _headers(token)),
    );
    _ensureSuccess(response);
    return _decodeMap(response);
  }

  Future<http.Response> _authorized(
    Future<http.Response> Function(String token) send,
  ) async {
    var token = await sessionToken();
    var response = await _perform(() => send(token));
    if (response.statusCode == 401) {
      _clearSession();
      token = await sessionToken();
      response = await _perform(() => send(token));
    }
    return response;
  }

  Future<http.Response> _perform(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('The daemon did not respond in time.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the daemon: ${error.message}');
    } on Exception catch (error) {
      throw ApiException('Could not reach the daemon: $error');
    }
  }

  void _clearSession() {
    _sessionToken = null;
    _sessionExpiresAt = null;
  }

  Map<String, String> _headers(String token) => {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = Uri.parse(settings.normalizedServerUrl);
    var prefix = base.path;
    if (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return base.replace(
      path: '$prefix$path',
      queryParameters: query,
      fragment: null,
    );
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFrom(response);
    }
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through to the error below.
    }
    throw ApiException(
      'The daemon returned an unexpected response (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  ApiException _errorFrom(http.Response response) {
    String? message;
    String? code;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          message = error['message'] as String?;
          code = error['code'] as String?;
        }
      }
    } on FormatException {
      // Keep the generic message.
    }
    return ApiException(
      message ?? 'Request failed (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
      code: code,
    );
  }
}
