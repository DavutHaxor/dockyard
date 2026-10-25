import 'package:dockyard/core/models/container.dart';
import 'package:dockyard/core/models/metrics_sample.dart';
import 'package:dockyard/core/state/live_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DockerContainer', () {
    test('parses the daemon payload', () {
      final container = DockerContainer.fromJson({
        'id': 'abc123',
        'name': 'traefik',
        'image': 'traefik:v3',
        'state': 'running',
        'status': 'Up 2 hours',
        'created': 1710000000,
        'ports': [
          {
            'private_port': 80,
            'public_port': 8080,
            'type': 'tcp',
            'ip': '0.0.0.0',
          },
          {'private_port': 443, 'type': 'tcp'},
        ],
      });

      expect(container.name, 'traefik');
      expect(container.isRunning, isTrue);
      expect(container.canStart, isFalse);
      expect(container.portLabels, ['8080 → 80/tcp', '443/tcp']);
    });

    test('treats missing values defensively', () {
      final container = DockerContainer.fromJson(const {});
      expect(container.name, 'unknown');
      expect(container.state, 'unknown');
      expect(container.ports, isEmpty);
      expect(container.isStopped, isTrue);
    });

    test('exposes labels for container actions', () {
      expect(ContainerAction.start.label, 'Start');
      expect(ContainerAction.stop.wireName, 'stop');
      expect(ContainerAction.restart.label, 'Restart');
    });
  });

  group('MetricsSample', () {
    test('parses nested memory and disk data', () {
      final sample = MetricsSample.fromJson({
        'timestamp': '2026-10-25T12:00:00Z',
        'cpu_percent': 12.5,
        'cpu_count': 8,
        'load_1': 0.4,
        'load_5': 0.3,
        'load_15': 0.2,
        'uptime_seconds': 86400,
        'memory': {
          'total_bytes': 1024,
          'used_bytes': 512,
          'available_bytes': 512,
          'percent': 50,
        },
        'disk': {
          'path': '/',
          'total_bytes': 2048,
          'used_bytes': 1024,
          'free_bytes': 1024,
          'percent': 50,
        },
      });

      expect(sample.cpuPercent, 12.5);
      expect(sample.cpuCount, 8);
      expect(sample.memory.totalBytes, 1024);
      expect(sample.disk.path, '/');
      expect(sample.timestamp, DateTime.utc(2026, 10, 25, 12));
    });
  });

  group('LiveState', () {
    test('derives histories and running counts', () {
      final running = DockerContainer.fromJson({
        'id': 'a',
        'name': 'a',
        'state': 'running',
      });
      final stopped = DockerContainer.fromJson({
        'id': 'b',
        'name': 'b',
        'state': 'exited',
      });
      final sample = MetricsSample.fromJson({
        'timestamp': '2026-10-25T12:00:00Z',
        'cpu_percent': 25,
        'memory': {'percent': 40},
        'disk': {'percent': 60},
      });

      final state = LiveState(
        configured: true,
        status: LiveStatus.live,
        history: [sample],
        containers: [running, stopped],
      );

      expect(state.latest, sample);
      expect(state.cpuHistory, [25]);
      expect(state.memoryHistory, [40]);
      expect(state.diskHistory, [60]);
      expect(state.runningContainers, 1);
    });

    test('clearMessage removes a previous error', () {
      const state = LiveState(
        configured: true,
        status: LiveStatus.error,
        message: 'offline',
      );

      final recovered = state.copyWith(
        status: LiveStatus.live,
        clearMessage: true,
      );
      expect(recovered.message, isNull);
      expect(recovered.status, LiveStatus.live);
    });
  });
}
