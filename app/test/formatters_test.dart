import 'package:dockyard/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('handles zero and units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
    });
  });

  group('formatPercent', () {
    test('uses one decimal below ten percent', () {
      expect(formatPercent(5.25), '5.3%');
      expect(formatPercent(12.44), '12%');
      expect(formatPercent(double.nan), '—');
    });
  });

  group('formatUptime', () {
    test('picks the largest useful unit', () {
      expect(formatUptime(42), '42s');
      expect(formatUptime(125), '2m');
      expect(formatUptime(3 * 3600 + 5 * 60), '3h 5m');
      expect(formatUptime(2 * 86400 + 3 * 3600), '2d 3h');
      expect(formatUptime(0), '—');
    });
  });

  test('formatLoad keeps two decimals', () {
    expect(formatLoad(0.456), '0.46');
    expect(formatLoad(double.infinity), '—');
  });

  test('formatClock renders a zero padded local time', () {
    expect(formatClock(DateTime(2026, 1, 2, 9, 5, 3)), '09:05:03');
    expect(formatClock(null), '—');
  });

  test('formatRelativeTime handles null and recent times', () {
    expect(formatRelativeTime(null), 'never');
    expect(formatRelativeTime(DateTime.now()), 'just now');
    expect(
      formatRelativeTime(DateTime.now().subtract(const Duration(minutes: 5))),
      '5m ago',
    );
  });
}
