class MemoryUsage {
  const MemoryUsage({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.percent,
  });

  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final double percent;

  factory MemoryUsage.fromJson(Map<String, dynamic> json) => MemoryUsage(
    totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
    usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
    availableBytes: (json['available_bytes'] as num?)?.toInt() ?? 0,
    percent: (json['percent'] as num?)?.toDouble() ?? 0,
  );
}

class DiskUsage {
  const DiskUsage({
    required this.path,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.percent,
  });

  final String path;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double percent;

  factory DiskUsage.fromJson(Map<String, dynamic> json) => DiskUsage(
    path: json['path'] as String? ?? '/',
    totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
    usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
    freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
    percent: (json['percent'] as num?)?.toDouble() ?? 0,
  );
}

class MetricsSample {
  const MetricsSample({
    required this.timestamp,
    required this.cpuPercent,
    required this.cpuCount,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.uptimeSeconds,
    required this.memory,
    required this.disk,
  });

  final DateTime timestamp;
  final double cpuPercent;
  final int cpuCount;
  final double load1;
  final double load5;
  final double load15;
  final double uptimeSeconds;
  final MemoryUsage memory;
  final DiskUsage disk;

  factory MetricsSample.fromJson(Map<String, dynamic> json) => MetricsSample(
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ??
        DateTime.now().toUtc(),
    cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0,
    cpuCount: (json['cpu_count'] as num?)?.toInt() ?? 0,
    load1: (json['load_1'] as num?)?.toDouble() ?? 0,
    load5: (json['load_5'] as num?)?.toDouble() ?? 0,
    load15: (json['load_15'] as num?)?.toDouble() ?? 0,
    uptimeSeconds: (json['uptime_seconds'] as num?)?.toDouble() ?? 0,
    memory: MemoryUsage.fromJson(
      json['memory'] as Map<String, dynamic>? ?? const {},
    ),
    disk: DiskUsage.fromJson(json['disk'] as Map<String, dynamic>? ?? const {}),
  );
}
