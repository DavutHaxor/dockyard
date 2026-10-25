String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : decimals;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatPercent(double value) {
  if (!value.isFinite) return '—';
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}%';
}

String formatUptime(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '—';
  final total = seconds.round();
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;

  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${total}s';
}

String formatLoad(double value) =>
    value.isFinite ? value.toStringAsFixed(2) : '—';

String formatClock(DateTime? time) {
  if (time == null) return '—';
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String formatRelativeTime(DateTime? time) {
  if (time == null) return 'never';
  final seconds = DateTime.now().difference(time).inSeconds;
  if (seconds < 2) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h ago';
  return '${hours ~/ 24}d ago';
}

String _two(int value) => value.toString().padLeft(2, '0');
