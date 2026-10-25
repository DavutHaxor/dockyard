import 'package:flutter/material.dart';

import '../../core/models/container.dart';

class ContainerTile extends StatelessWidget {
  const ContainerTile({
    super.key,
    required this.container,
    required this.busy,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final DockerContainer container;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stateColor = _stateColor(theme, container);
    final labels = container.portLabels;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_stateIcon(container), color: stateColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          container.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StateChip(label: container.state, color: stateColor),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    container.image,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (container.status.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      container.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (labels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final label in labels.take(4))
                          _PortChip(label: label),
                        if (labels.length > 4)
                          _PortChip(label: '+${labels.length - 4}'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (container.canStart)
                    IconButton.filledTonal(
                      tooltip: 'Start',
                      visualDensity: VisualDensity.compact,
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    ),
                  if (container.isRunning || container.isPaused)
                    IconButton.filledTonal(
                      tooltip: 'Stop',
                      visualDensity: VisualDensity.compact,
                      onPressed: onStop,
                      icon: const Icon(Icons.stop_rounded, size: 20),
                    ),
                  IconButton(
                    tooltip: 'Restart',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRestart,
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _stateColor(ThemeData theme, DockerContainer container) {
    final scheme = theme.colorScheme;
    if (container.isRunning) {
      return theme.brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green.shade700;
    }
    if (container.isPaused) {
      return theme.brightness == Brightness.dark
          ? Colors.orange.shade300
          : Colors.orange.shade800;
    }
    return scheme.onSurfaceVariant;
  }

  IconData _stateIcon(DockerContainer container) {
    if (container.isRunning) return Icons.play_circle_fill_rounded;
    if (container.isPaused) return Icons.pause_circle_filled_rounded;
    return Icons.stop_circle_outlined;
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PortChip extends StatelessWidget {
  const _PortChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
