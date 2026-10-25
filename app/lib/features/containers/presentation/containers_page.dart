import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_controller.dart';
import '../../../core/models/container.dart';
import '../../../core/state/live_controller.dart';
import '../../../core/state/live_state.dart';
import '../../../core/state/navigation.dart';
import '../../../shared/widgets/connection_banner.dart';
import '../../../shared/widgets/container_tile.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_scaffold.dart';

enum _ContainerFilter { all, running, stopped }

class ContainersPage extends ConsumerStatefulWidget {
  const ContainersPage({super.key});

  @override
  ConsumerState<ContainersPage> createState() => _ContainersPageState();
}

class _ContainersPageState extends ConsumerState<ContainersPage> {
  final _search = TextEditingController();
  _ContainerFilter _filter = _ContainerFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);

    if (!settings.isConfigured) {
      return PageScaffold(
        title: 'Containers',
        subtitle: 'Start, stop, and restart workloads on the daemon host.',
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No daemon configured',
          message:
              'Add your server URL and admin token to see the containers '
              'running on your homelab host.',
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
    final filtered = _applyFilter(live.containers);
    final showBanner =
        live.status == LiveStatus.error ||
        live.status == LiveStatus.reconnecting;

    return PageScaffold(
      title: 'Containers',
      subtitle:
          '${live.runningContainers} running · '
          '${live.containers.length} total',
      actions: [
        IconButton.outlined(
          tooltip: 'Refresh',
          onPressed: () => _refresh(context),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBanner)
            ConnectionBanner(
              status: live.status,
              message: live.message,
              onRetry: ref.read(liveControllerProvider.notifier).retry,
            ),
          _Filters(
            searchController: _search,
            filter: _filter,
            visibleCount: filtered.length,
            totalCount: live.containers.length,
            onSearchChanged: (_) => setState(() {}),
            onFilterChanged: (filter) => setState(() => _filter = filter),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyList(
                    hasContainers: live.containers.isEmpty,
                    searching: _search.text.trim().isNotEmpty,
                    filter: _filter,
                    status: live.status,
                    message: live.message,
                    onRefresh: () => _refresh(context),
                    onClear: () {
                      _search.clear();
                      setState(() => _filter = _ContainerFilter.all);
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 28),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final container = filtered[index];
                      return ContainerTile(
                        container: container,
                        busy: live.pendingActions.contains(container.id),
                        onStart: () =>
                            _performAction(container, ContainerAction.start),
                        onStop: () =>
                            _performAction(container, ContainerAction.stop),
                        onRestart: () =>
                            _performAction(container, ContainerAction.restart),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<DockerContainer> _applyFilter(List<DockerContainer> containers) {
    final query = _search.text.trim().toLowerCase();
    return containers
        .where((container) {
          final matchesFilter = switch (_filter) {
            _ContainerFilter.all => true,
            _ContainerFilter.running => container.isRunning,
            _ContainerFilter.stopped => !container.isRunning,
          };
          if (!matchesFilter) return false;
          if (query.isEmpty) return true;
          return container.name.toLowerCase().contains(query) ||
              container.image.toLowerCase().contains(query) ||
              container.state.toLowerCase().contains(query) ||
              container.id.toLowerCase().startsWith(query);
        })
        .toList(growable: false);
  }

  Future<void> _refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(liveControllerProvider.notifier).refresh();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _performAction(
    DockerContainer container,
    ContainerAction action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(liveControllerProvider.notifier)
          .performAction(container.id, action);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${action.label} requested for ${container.name}.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${action.label} failed: $error')),
      );
    }
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.filter,
    required this.visibleCount,
    required this.totalCount,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final TextEditingController searchController;
  final _ContainerFilter filter;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ContainerFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final search = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Search by name, image, or state',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        isDense: true,
      ),
    );

    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final option in _ContainerFilter.values)
          ChoiceChip(
            label: Text(switch (option) {
              _ContainerFilter.all => 'All',
              _ContainerFilter.running => 'Running',
              _ContainerFilter.stopped => 'Stopped',
            }),
            selected: filter == option,
            onSelected: (_) => onFilterChanged(option),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '$visibleCount of $totalCount',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              SizedBox(width: 340, child: search),
              const SizedBox(width: 16),
              Expanded(child: chips),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [search, const SizedBox(height: 10), chips],
        );
      },
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({
    required this.hasContainers,
    required this.searching,
    required this.filter,
    required this.status,
    required this.message,
    required this.onRefresh,
    required this.onClear,
  });

  final bool hasContainers;
  final bool searching;
  final _ContainerFilter filter;
  final LiveStatus status;
  final String? message;
  final VoidCallback onRefresh;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!hasContainers) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: status == LiveStatus.error
            ? 'No container data'
            : 'No containers found',
        message: status == LiveStatus.error
            ? message ?? 'The Docker Engine on the daemon host is unreachable.'
            : 'Dockyard did not receive any containers from the daemon. '
                  'Create one with Docker Compose and it will appear here.',
        action: OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      );
    }

    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No matching containers',
      message: _filteredOutMessage,
      action: TextButton.icon(
        onPressed: onClear,
        icon: const Icon(Icons.filter_alt_off_rounded),
        label: const Text('Clear filters'),
      ),
    );
  }

  String get _filteredOutMessage {
    if (searching && filter != _ContainerFilter.all) {
      return 'No containers match your search and filter.';
    }
    if (searching) return 'No containers match your search.';
    return 'There are no containers in this state right now.';
  }
}
