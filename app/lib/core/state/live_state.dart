import '../models/container.dart';
import '../models/metrics_sample.dart';

enum LiveStatus { disabled, connecting, live, reconnecting, error }

class LiveState {
  const LiveState({
    required this.configured,
    required this.status,
    this.message,
    this.history = const [],
    this.containers = const [],
    this.pendingActions = const {},
    this.lastUpdated,
  });

  final bool configured;
  final LiveStatus status;
  final String? message;
  final List<MetricsSample> history;
  final List<DockerContainer> containers;
  final Set<String> pendingActions;
  final DateTime? lastUpdated;

  MetricsSample? get latest => history.isEmpty ? null : history.last;

  List<double> get cpuHistory =>
      history.map((sample) => sample.cpuPercent).toList(growable: false);

  List<double> get memoryHistory =>
      history.map((sample) => sample.memory.percent).toList(growable: false);

  List<double> get diskHistory =>
      history.map((sample) => sample.disk.percent).toList(growable: false);

  int get runningContainers =>
      containers.where((container) => container.isRunning).length;

  LiveState copyWith({
    bool? configured,
    LiveStatus? status,
    String? message,
    bool clearMessage = false,
    List<MetricsSample>? history,
    List<DockerContainer>? containers,
    Set<String>? pendingActions,
    DateTime? lastUpdated,
  }) => LiveState(
    configured: configured ?? this.configured,
    status: status ?? this.status,
    message: clearMessage ? null : (message ?? this.message),
    history: history ?? this.history,
    containers: containers ?? this.containers,
    pendingActions: pendingActions ?? this.pendingActions,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}
