import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/live_controller.dart';
import '../../../core/state/navigation.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../containers/presentation/containers_page.dart';
import '../../metrics/presentation/metrics_page.dart';
import '../../overview/presentation/overview_page.dart';
import '../../settings/presentation/settings_page.dart';

/// Desktop shell: a permanent navigation rail on the left with the four
/// sections of the app. There is deliberately no login route; connection
/// details live on the Settings page.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _pages = <Widget>[
    OverviewPage(),
    ContainersPage(),
    MetricsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(selectedSectionProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final extended = constraints.maxWidth >= 1080;
            return Row(
              children: [
                NavigationRail(
                  extended: extended,
                  minExtendedWidth: 232,
                  selectedIndex: section.index,
                  labelType: extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  leading: Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, extended ? 8 : 20),
                    child: _Brand(extended: extended),
                  ),
                  leadingAtTop: true,
                  trailingAtBottom: true,
                  trailing: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: _RailStatus(extended: extended),
                  ),
                  onDestinationSelected: (index) {
                    ref.read(selectedSectionProvider.notifier).state =
                        AppSection.values[index];
                  },
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      selectedIcon: Icon(Icons.space_dashboard_rounded),
                      label: Text('Overview'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2_rounded),
                      label: Text('Containers'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights_rounded),
                      label: Text('Metrics'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune_rounded),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (var index = 0; index < _pages.length; index++)
                        Offstage(
                          offstage: section.index != index,
                          child: TickerMode(
                            enabled: section.index == index,
                            child: _pages[index],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mark = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        Icons.sailing_rounded,
        color: scheme.onPrimaryContainer,
        size: 24,
      ),
    );

    if (!extended) {
      return Tooltip(message: 'Dockyard', child: mark);
    }

    return SizedBox(
      width: 200,
      child: Row(
        children: [
          mark,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Dockyard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Homelab console',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _RailStatus extends ConsumerWidget {
  const _RailStatus({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveControllerProvider);

    return StatusPill(status: live.status, compact: !extended);
  }
}
