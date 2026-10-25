import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/settings.dart';
import '../config/settings_controller.dart';
import '../models/container.dart';
import '../models/metrics_sample.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'live_state.dart';

/// Owns the live WebSocket connection plus the latest metric window and
/// container list. One instance exists per configured server/token pair.
class LiveController extends StateNotifier<LiveState> {
  LiveController(this._api, this._settings)
    : super(
        LiveState(
          configured: _settings.isConfigured,
          status: _settings.isConfigured
              ? LiveStatus.connecting
              : LiveStatus.disabled,
        ),
      );

  static const _maxHistory = 300;

  final ApiClient _api;
  final DockyardSettings _settings;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  int _attempt = 0;
  int _generation = 0;
  bool _disposed = false;

  void start() {
    if (!_settings.isConfigured) return;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_disposed) return;

    final generation = ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _closeSocket();

    _update(
      (current) => current.copyWith(
        configured: true,
        status: current.history.isEmpty
            ? LiveStatus.connecting
            : LiveStatus.reconnecting,
        clearMessage: true,
      ),
    );

    try {
      final token = await _api.sessionToken();
      if (_disposed || generation != _generation) return;

      final channel = WebSocketChannel.connect(_api.webSocketUri(token));
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation) {
        unawaited(channel.sink.close());
        return;
      }

      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error) {
          if (_channel == channel) _handleDisconnect(_humanize(error));
        },
        onDone: () {
          if (_channel == channel) _handleDisconnect('Connection closed.');
        },
        cancelOnError: false,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _handleDisconnect(_humanize(error));
    }
  }

  /// Re-fetches the REST snapshot. Useful after container actions and from
  /// the refresh buttons. The WebSocket keeps running independently.
  Future<void> refresh() async {
    if (!_settings.isConfigured) return;

    try {
      final containers = await _api.listContainers();
      final history = await _api.metricsHistory();
      if (_disposed) return;

      final isLive = state.status == LiveStatus.live;
      _update(
        (current) => current.copyWith(
          configured: true,
          containers: containers,
          history: history.isEmpty ? current.history : _capHistory(history),
          lastUpdated: DateTime.now(),
          clearMessage: isLive,
        ),
      );

      if (state.status != LiveStatus.live && _retryTimer == null) {
        retry();
      }
    } catch (error) {
      if (_disposed) return;
      _update(
        (current) => current.copyWith(
          message: _humanize(error),
          status: current.status == LiveStatus.live
              ? LiveStatus.live
              : LiveStatus.error,
        ),
      );
      rethrow;
    }
  }

  /// Runs start/stop/restart and refreshes the list immediately. Throws
  /// [ApiException] so the page can surface the daemon's message.
  Future<void> performAction(String id, ContainerAction action) async {
    if (state.pendingActions.contains(id)) return;

    _update(
      (current) =>
          current.copyWith(pendingActions: {...current.pendingActions, id}),
    );

    try {
      await _api.containerAction(id, action);
      try {
        final containers = await _api.listContainers();
        if (!_disposed) {
          _update(
            (current) => current.copyWith(
              containers: containers,
              lastUpdated: DateTime.now(),
            ),
          );
        }
      } on ApiException {
        // The watcher/WebSocket will produce the next update.
      }
    } finally {
      if (!_disposed) {
        _update(
          (current) => current.copyWith(
            pendingActions: {...current.pendingActions}..remove(id),
          ),
        );
      }
    }
  }

  /// Drops the current socket and connects again with a fresh backoff.
  void retry() {
    if (!_settings.isConfigured || _disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    unawaited(_connect());
  }

  void _handleMessage(dynamic message) {
    if (_disposed) return;
    try {
      final raw = message is String
          ? message
          : utf8.decode(message as List<int>, allowMalformed: true);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'];
      final data = decoded['data'];
      if (type == 'snapshot') {
        _applySnapshot(data);
      } else if (type == 'metrics' && data is Map<String, dynamic>) {
        _appendSample(MetricsSample.fromJson(data));
      } else if (type == 'containers') {
        _applyContainers(data);
      }
    } catch (error) {
      // Ignore a malformed frame; the next snapshot re-syncs the client.
      debugPrint('Dockyard WebSocket frame ignored: $error');
    }
  }

  void _applySnapshot(dynamic data) {
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};

    final history = <MetricsSample>[];
    final rawHistory = map['history'];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map<String, dynamic>) {
          try {
            history.add(MetricsSample.fromJson(item));
          } catch (error) {
            debugPrint('Dockyard metric sample ignored: $error');
          }
        }
      }
    }

    final rawMetrics = map['metrics'];
    if (rawMetrics is Map<String, dynamic>) {
      final latest = MetricsSample.fromJson(rawMetrics);
      if (history.isEmpty || history.last.timestamp != latest.timestamp) {
        history.add(latest);
      }
    }

    _attempt = 0;
    _update(
      (current) => current.copyWith(
        configured: true,
        status: LiveStatus.live,
        clearMessage: true,
        history: _capHistory(history),
        containers: _parseContainers(map['containers']),
        lastUpdated: DateTime.now(),
      ),
    );
  }

  void _appendSample(MetricsSample sample) {
    _attempt = 0;
    _update(
      (current) => current.copyWith(
        configured: true,
        status: LiveStatus.live,
        clearMessage: true,
        history: _capHistory([...current.history, sample]),
        lastUpdated: DateTime.now(),
      ),
    );
  }

  void _applyContainers(dynamic data) {
    _attempt = 0;
    _update(
      (current) => current.copyWith(
        configured: true,
        status: LiveStatus.live,
        clearMessage: true,
        containers: _parseContainers(data),
        lastUpdated: DateTime.now(),
      ),
    );
  }

  List<DockerContainer> _parseContainers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DockerContainer.fromJson)
        .toList(growable: false);
  }

  List<MetricsSample> _capHistory(List<MetricsSample> samples) {
    if (samples.length <= _maxHistory) return samples;
    return samples.sublist(samples.length - _maxHistory);
  }

  void _handleDisconnect(String message) {
    if (_disposed) return;
    _closeSocket();
    _scheduleReconnect(message);
  }

  void _scheduleReconnect(String message) {
    if (_disposed || _retryTimer != null) return;

    _attempt = (_attempt + 1).clamp(1, 5);
    final delay = switch (_attempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 16,
      _ => 30,
    };
    _update(
      (current) => current.copyWith(
        status: _attempt >= 3 ? LiveStatus.error : LiveStatus.reconnecting,
        message: message,
      ),
    );
    _retryTimer = Timer(Duration(seconds: delay), () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }

  void _closeSocket() {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(channel.sink.close());
    }
  }

  String _humanize(Object error) {
    if (error is ApiException) return error.message;
    if (error is TimeoutException) return 'Timed out waiting for the daemon.';
    return error.toString();
  }

  void _update(LiveState Function(LiveState current) change) {
    if (_disposed) return;
    state = change(state);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _closeSocket();
    super.dispose();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  final client = ApiClient(settings: settings);
  ref.onDispose(client.close);
  return client;
});

final liveControllerProvider = StateNotifierProvider<LiveController, LiveState>(
  (ref) {
    final settings = ref.watch(settingsControllerProvider);
    final api = ref.watch(apiClientProvider);
    final controller = LiveController(api, settings);
    controller.start();
    return controller;
  },
);
