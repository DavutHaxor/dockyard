import 'package:flutter/material.dart';

import '../../core/state/live_state.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.compact = false});

  final LiveStatus status;
  final bool compact;

  static String labelFor(LiveStatus status) => switch (status) {
    LiveStatus.disabled => 'Setup needed',
    LiveStatus.connecting => 'Connecting',
    LiveStatus.live => 'Live',
    LiveStatus.reconnecting => 'Reconnecting',
    LiveStatus.error => 'Offline',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (status) {
      LiveStatus.disabled => scheme.onSurfaceVariant,
      LiveStatus.connecting || LiveStatus.reconnecting =>
        theme.brightness == Brightness.dark
            ? Colors.orange.shade300
            : Colors.orange.shade800,
      LiveStatus.live =>
        theme.brightness == Brightness.dark
            ? Colors.green.shade300
            : Colors.green.shade700,
      LiveStatus.error => scheme.error,
    };
    final label = labelFor(status);

    final pill = Container(
      padding: compact
          ? const EdgeInsets.all(9)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          if (!compact) ...[
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    return compact ? Tooltip(message: label, child: pill) : pill;
  }
}
