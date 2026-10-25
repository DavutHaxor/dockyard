class ContainerPort {
  const ContainerPort({
    required this.privatePort,
    required this.type,
    this.ip,
    this.publicPort,
  });

  final int privatePort;
  final int? publicPort;
  final String type;
  final String? ip;

  factory ContainerPort.fromJson(Map<String, dynamic> json) => ContainerPort(
    privatePort: (json['private_port'] as num?)?.toInt() ?? 0,
    publicPort: (json['public_port'] as num?)?.toInt(),
    type: json['type'] as String? ?? 'tcp',
    ip: json['ip'] as String?,
  );

  String get label {
    final host = publicPort == null ? '' : '$publicPort → ';
    return '$host$privatePort/$type';
  }
}

enum ContainerAction {
  start,
  stop,
  restart;

  String get wireName => name;

  String get label => switch (this) {
    ContainerAction.start => 'Start',
    ContainerAction.stop => 'Stop',
    ContainerAction.restart => 'Restart',
  };
}

class DockerContainer {
  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.created,
    required this.ports,
  });

  final String id;
  final String name;
  final String image;
  final String state;
  final String status;
  final int created;
  final List<ContainerPort> ports;

  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    final rawPorts = json['ports'];
    return DockerContainer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      image: json['image'] as String? ?? '',
      state: json['state'] as String? ?? 'unknown',
      status: json['status'] as String? ?? '',
      created: (json['created'] as num?)?.toInt() ?? 0,
      ports: rawPorts is List
          ? rawPorts
                .whereType<Map<String, dynamic>>()
                .map(ContainerPort.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  bool get isRunning => state == 'running';
  bool get isPaused => state == 'paused';
  bool get isStopped => !isRunning && !isPaused;
  bool get canStart => !isRunning && !isPaused;

  List<String> get portLabels =>
      ports.map((port) => port.label).toList(growable: false);
}
