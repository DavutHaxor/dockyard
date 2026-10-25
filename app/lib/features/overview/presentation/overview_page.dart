import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_controller.dart';
import '../../../core/models/container.dart';
import '../../../core/models/metrics_sample.dart';
import '../../../core/state/live_controller.dart';
import '../../../core/state/live_state.dart';
import '../../../core/state/navigation.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/connection_banner.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/metric_tile.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/sparkline.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final live = ref.watch(liveControllerProvider);

    if (!settings.isConfigured) {
      return PageScaffold(
        title: 'Overview',
        subtitle: 'A dashboard for the Docker host running your daemon.',
        child: EmptyState(
          icon: Icons.rocket_launch_rounded,
          title: 'Connect your daemon',
          message:
              'Add the daemon URL and admin token in Settings. Dockyard signs '
              'in automatically and keeps the dashboard live in the background.',
          action: FilledButton.icon(
            onPressed: () => ref.read(selectedSectionProvider.notifier).state =
                AppSection.settings,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Open settings'),
          ),
        ),
      );
    }

    final latest = live.latest;
    final actions = <Widget>[
      IconButton.outlined(
        tooltip: 'Refresh',
        onPressed: () => _refresh(context, ref),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ];

    if (latest == null) {
      return PageScaffold(
        title: 'Overview',
        subtitle: settings.normalizedServerUrl,
        actions: actions,
        child: switch (live.status) {
          LiveStatus.error || LiveStatus.reconnecting => Column(
            children: [
              ConnectionBanner(
                status: live.status,
                message: live.message,
                onRetry: ref.read(liveControllerProvider.notifier).retry,
              ),
              Expanded(
                child: EmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'Waiting for the first sample',
                  message:
                      live.message ??
                      'The daemon is not sending metrics yet. It may still be '
                          'starting or Docker may be unavailable.',
                  action: OutlinedButton.icon(
                    onPressed: ref.read(liveControllerProvider.notifier).retry,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Reconnect'),
                  ),
                ),
              ),
            ],
          ),
          _ => const _ConnectingState(),
        },
      );
    }

    return PageScaffold(
      title: 'Overview',
      subtitle: settings.normalizedServerUrl,
      actions: actions,
      child: SingleChildScrollView(
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
            const _SectionHeader(title: 'Live metrics'),
            const SizedBox(height: 12),
            _MetricGrid(sample: latest, live: live),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'System'),
            const SizedBox(height: 12),
            _SystemCard(sample: latest, lastUpdated: live.lastUpdated),
            const SizedBox(height: 28),
            _SectionHeader(
              title: 'Containers',
              subtitle: live.containers.isEmpty
                  ? null
                  : '${live.runningContainers} running · '
                        '${live.containers.length} total',
              trailing: TextButton.icon(
                onPressed: () =>
                    ref.read(selectedSectionProvider.notifier).state =
                        AppSection.containers,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('View all'),
              ),
            ),
            const SizedBox(height: 12),
            _ContainerPreview(
              containers: live.containers,
              onRefresh: () => _refresh(context, ref),
            ),
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

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.sample, required this.live});

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

        Widget tile({
          required String label,
          required String value,
          required String detail,
          required IconData icon,
          required Color color,
          required List<double> history,
          required double progress,
        }) => SizedBox(
          width: width,
          child: MetricTile(
            label: label,
            value: value,
            detail: detail,
            icon: icon,
            accent: color,
            progress: progress,
            chart: Sparkline(
              values: history,
              color: color,
              height: 44,
              strokeWidth: 1.8,
            ),
          ),
        );

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            tile(
              label: 'CPU',
              value: formatPercent(sample.cpuPercent),
              detail:
                  '${sample.cpuCount} cores · load '
                  '${formatLoad(sample.load1)}',
              icon: Icons.memory_rounded,
              color: scheme.primary,
              history: live.cpuHistory,
              progress: sample.cpuPercent / 100,
            ),
            tile(
              label: 'Memory',
              value: formatPercent(sample.memory.percent),
              detail:
                  '${formatBytes(sample.memory.usedBytes)} of '
                  '${formatBytes(sample.memory.totalBytes)}',
              icon: Icons.developer_board_rounded,
              color: scheme.tertiary,
              history: live.memoryHistory,
              progress: sample.memory.percent / 100,
            ),
            tile(
              label: 'Disk',
              value: formatPercent(sample.disk.percent),
              detail:
                  '${formatBytes(sample.disk.usedBytes)} of '
                  '${formatBytes(sample.disk.totalBytes)}',
              icon: Icons.storage_rounded,
              color: scheme.secondary,
              history: live.diskHistory,
              progress: sample.disk.percent / 100,
            ),
          ],
        );
      },
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.sample, required this.lastUpdated});

  final MetricsSample sample;
  final DateTime? lastUpdated;

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
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 36,
          runSpacing: 20,
          children: [
            _InfoItem(
              icon: Icons.schedule_rounded,
              label: 'Uptime',
              value: formatUptime(sample.uptimeSeconds),
            ),
            _InfoItem(
              icon: Icons.speed_rounded,
              label: 'Load average',
              value:
                  '${formatLoad(sample.load1)} / '
                  '${formatLoad(sample.load5)} / ${formatLoad(sample.load15)}',
            ),
            _InfoItem(
              icon: Icons.memory_rounded,
              label: 'CPU cores',
              value: '${sample.cpuCount}',
            ),
            _InfoItem(
              icon: Icons.developer_board_rounded,
              label: 'Memory free',
              value: formatBytes(sample.memory.availableBytes),
            ),
            _InfoItem(
              icon: Icons.storage_rounded,
              label: 'Disk free',
              value: formatBytes(sample.disk.freeBytes),
            ),
            _InfoItem(
              icon: Icons.update_rounded,
              label: 'Last sample',
              value: formatClock(sample.timestamp),
            ),
            _InfoItem(
              icon: Icons.cloud_done_rounded,
              label: 'Last sync',
              value: formatRelativeTime(lastUpdated),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
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
          ),
        ],
      ),
    );
  }
}

class _ContainerPreview extends StatelessWidget {
  const _ContainerPreview({required this.containers, required this.onRefresh});

  final List<DockerContainer> containers;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (containers.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.inbox_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No containers reported yet. The Docker socket may be '
                  'unavailable on the daemon host.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onRefresh, child: const Text('Refresh')),
            ],
          ),
        ),
      );
    }

    final preview = containers.take(5).toList(growable: false);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < preview.length; index++) ...[
            _PreviewRow(container: preview[index]),
            if (index != preview.length - 1)
              Divider(
                height: 1,
                indent: 64,
                color: scheme.outlineVariant.withValues(alpha: 0.55),
              ),
          ],
          if (containers.length > preview.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+${containers.length - preview.length} more containers',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.container});

  final DockerContainer container;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = container.isRunning
        ? (theme.brightness == Brightness.dark
              ? Colors.green.shade300
              : Colors.green.shade700)
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              container.isRunning
                  ? Icons.play_circle_fill_rounded
                  : Icons.stop_circle_outlined,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  container.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  container.image,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            container.state,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (trailing != null) ?trailing,
      ],
    );
  }
}

class _ConnectingState extends StatelessWidget {
  const _ConnectingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Connecting to the daemon…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
