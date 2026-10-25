import 'package:flutter/material.dart';

import '../../core/state/live_state.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.status,
    required this.message,
    required this.onRetry,
  });

  final LiveStatus status;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isError = status == LiveStatus.error;
    final background = isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              isError ? Icons.cloud_off_rounded : Icons.sync_problem_rounded,
              color: foreground,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message?.trim().isNotEmpty == true
                    ? message!
                    : isError
                    ? 'The daemon is unreachable.'
                    : 'Reconnecting to the daemon…',
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: foreground),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
