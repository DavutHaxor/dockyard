import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_controller.dart';
import '../../../core/models/metrics_sample.dart';
import '../../../core/state/live_controller.dart';
import '../../../core/state/live_state.dart';
import '../../../core/state/navigation.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/connection_banner.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/sparkline.dart';

class MetricsPage extends ConsumerWidget {
  const MetricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    if (!settings.isConfigured) {
      return PageScaffold(
        title: 'Metrics',
        subtitle: 'CPU, memory, disk, and load for the daemon host.',
        child: EmptyState(
          icon: Icons.insights_outlined,
          title: 'No metrics yet',
          message:
              'Connect Dockyard to your daemon to stream host metrics in '
              'real time.',
          action: FilledButton.icon(
            onPressed: () => ref.read(selectedSectionProvider.notifier).state =
                AppSection.settings,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Open settings'),
          ),
        ),
      );
    }

    final live = ref.watch(liveControllerProvider);
    final latest = live.latest;

    return PageScaffold(
      title: 'Metrics',
      subtitle: latest == null
          ? settings.normalizedServerUrl
          : '${live.history.length}-sample window · '
                '${settings.normalizedServerUrl}',
      actions: [
        IconButton.outlined(
          tooltip: 'Refresh',
          onPressed: () => _refresh(context, ref),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: latest == null
          ? switch (live.status) {
              LiveStatus.error || LiveStatus.reconnecting => Column(
                children: [
                  ConnectionBanner(
                    status: live.status,
                    message: live.message,
                    onRetry: ref.read(liveControllerProvider.notifier).retry,
                  ),
                  Expanded(
                    child: EmptyState(
                      icon: Icons.timeline_rounded,
                      title: 'No samples collected',
                      message:
                          live.message ??
                          'The daemon has not produced a metrics sample yet.',
                      action: OutlinedButton.icon(
                        onPressed: ref
                            .read(liveControllerProvider.notifier)
                            .retry,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Reconnect'),
                      ),
                    ),
                  ),
                ],
              ),
              _ => const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            }
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live.status == LiveStatus.error ||
                      live.status == LiveStatus.reconnecting)
                    ConnectionBanner(
                      status: live.status,
                      message: live.message,
                      onRetry: ref.read(liveControllerProvider.notifier).retry,
                    ),
                  const _SectionHeader(title: 'Trends'),
                  const SizedBox(height: 12),
                  _ChartsGrid(sample: latest, live: live),
                  const SizedBox(height: 28),
                  const _SectionHeader(title: 'System details'),
                  const SizedBox(height: 12),
                  _DetailsCard(sample: latest, live: live),
                ],
              ),
            ),
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(liveControllerProvider.notifier).refresh();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _ChartsGrid extends StatelessWidget {
  const _ChartsGrid({required this.sample, required this.live});

  final MetricsSample sample;
  final LiveState live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        Widget chart({
          required String title,
          required IconData icon,
          required Color color,
          required double percent,
          required String detail,
          required List<double> values,
        }) => SizedBox(
          width: width,
          child: _ChartCard(
            title: title,
            icon: icon,
            color: color,
            percent: percent,
            detail: detail,
            values: values,
          ),
        );

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            chart(
              title: 'CPU usage',
              icon: Icons.memory_rounded,
              color: scheme.primary,
              percent: sample.cpuPercent,
              detail:
                  '${sample.cpuCount} cores · '
                  '${formatLoad(sample.load1)} load (1m)',
              values: live.cpuHistory,
            ),
            chart(
              title: 'Memory usage',
              icon: Icons.developer_board_rounded,
              color: scheme.tertiary,
              percent: sample.memory.percent,
              detail:
                  '${formatBytes(sample.memory.usedBytes)} used · '
                  '${formatBytes(sample.memory.totalBytes)} total',
              values: live.memoryHistory,
            ),
            chart(
              title: 'Disk usage',
              icon: Icons.storage_rounded,
              color: scheme.secondary,
              percent: sample.disk.percent,
              detail:
                  '${formatBytes(sample.disk.usedBytes)} used on '
                  '${sample.disk.path}',
              values: live.diskHistory,
            ),
          ],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.percent,
    required this.detail,
    required this.values,
  });

  final String title;
  final IconData icon;
  final Color color;
  final double percent;
  final String detail;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  formatPercent(percent),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Sparkline(
              values: values,
              color: color,
              height: 108,
              strokeWidth: 2,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  values.isEmpty ? 'No samples' : '${values.length} samples',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '0–100%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.sample, required this.live});

  final MetricsSample sample;
  final LiveState live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final oldest = live.history.isEmpty ? null : live.history.first.timestamp;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 32,
          runSpacing: 20,
          children: [
            _Detail(label: 'Uptime', value: formatUptime(sample.uptimeSeconds)),
            _Detail(label: 'CPU cores', value: '${sample.cpuCount}'),
            _Detail(
              label: 'Load average',
              value:
                  '${formatLoad(sample.load1)} · '
                  '${formatLoad(sample.load5)} · '
                  '${formatLoad(sample.load15)}',
            ),
            _Detail(
              label: 'Memory used',
              value:
                  '${formatBytes(sample.memory.usedBytes)} / '
                  '${formatBytes(sample.memory.totalBytes)}',
            ),
            _Detail(
              label: 'Memory available',
              value: formatBytes(sample.memory.availableBytes),
            ),
            _Detail(
              label: 'Disk used',
              value:
                  '${formatBytes(sample.disk.usedBytes)} / '
                  '${formatBytes(sample.disk.totalBytes)}',
            ),
            _Detail(
              label: 'Disk free',
              value: formatBytes(sample.disk.freeBytes),
            ),
            _Detail(label: 'Filesystem', value: sample.disk.path),
            _Detail(
              label: 'Latest sample',
              value: formatClock(sample.timestamp),
            ),
            _Detail(label: 'Oldest in window', value: formatClock(oldest)),
            _Detail(
              label: 'Window size',
              value: '${live.history.length} samples',
            ),
            _Detail(
              label: 'Last sync',
              value: formatRelativeTime(live.lastUpdated),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
