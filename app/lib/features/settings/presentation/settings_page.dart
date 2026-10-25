import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings.dart';
import '../../../core/config/settings_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/state/live_controller.dart';
import '../../../core/state/live_state.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/status_pill.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverController;
  late final TextEditingController _tokenController;

  bool _obscureToken = true;
  bool _saving = false;
  bool _testing = false;
  _TestResult? _testResult;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsControllerProvider);
    _serverController = TextEditingController(text: settings.serverUrl);
    _tokenController = TextEditingController(text: settings.adminToken);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Settings',
      subtitle: 'Connection details for your Dockyard daemon.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 28),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 820
                ? constraints.maxWidth
                : 820.0;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsSection(
                      icon: Icons.lan_rounded,
                      title: 'Daemon connection',
                      subtitle:
                          'Dockyard exchanges the admin token for a short-lived '
                          'session in the background. No login screen is involved.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _serverController,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  validator: DockyardSettings.validateServerUrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Server URL',
                                    hintText: 'http://192.168.1.10:8080',
                                    helperText:
                                        'Full URL including scheme and port.',
                                    prefixIcon: Icon(Icons.link_rounded),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _tokenController,
                                  obscureText: _obscureToken,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  validator:
                                      DockyardSettings.validateAdminToken,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: 'Admin token',
                                    hintText: 'DOCKYARD_ADMIN_TOKEN',
                                    helperText:
                                        'Must match the token configured on the '
                                        'daemon.',
                                    prefixIcon: const Icon(Icons.key_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: _obscureToken
                                          ? 'Show token'
                                          : 'Hide token',
                                      onPressed: () => setState(
                                        () => _obscureToken = !_obscureToken,
                                      ),
                                      icon: Icon(
                                        _obscureToken
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded, size: 18),
                                label: const Text('Save settings'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _testing ? null : _testConnection,
                                icon: _testing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.wifi_tethering_rounded,
                                        size: 18,
                                      ),
                                label: const Text('Test connection'),
                              ),
                              TextButton.icon(
                                onPressed: _tokenController.text.isEmpty
                                    ? null
                                    : _confirmClearToken,
                                icon: const Icon(
                                  Icons.key_off_rounded,
                                  size: 18,
                                ),
                                label: const Text('Clear token'),
                              ),
                            ],
                          ),
                          if (_testResult case final result?) ...[
                            const SizedBox(height: 16),
                            _TestBanner(result: result),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _LiveStatusSection(),
                    const SizedBox(height: 16),
                    const _AboutSection(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .save(
            DockyardSettings(
              serverUrl: _serverController.text,
              adminToken: _tokenController.text,
            ),
          );
      if (!mounted) return;
      setState(() => _testResult = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection settings saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final candidate = DockyardSettings(
      serverUrl: _serverController.text,
      adminToken: _tokenController.text,
    ).normalized();
    final client = ApiClient(settings: candidate);

    try {
      await client.testConnection();
      if (!mounted) return;
      setState(
        () => _testResult = const _TestResult(
          ok: true,
          message:
              'Authenticated with the daemon successfully. '
              'Save the settings to connect.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _testResult = _TestResult(ok: false, message: error.toString()),
      );
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _confirmClearToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear admin token?'),
        content: const Text(
          'Live updates and container actions will stop until you add a token '
          'again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear token'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _tokenController.clear();
    await ref.read(settingsControllerProvider.notifier).clearToken();
    if (!mounted) return;
    setState(() => _testResult = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Admin token cleared.')));
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _LiveStatusSection extends ConsumerWidget {
  const _LiveStatusSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final live = ref.watch(liveControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SettingsSection(
      icon: Icons.sensors_rounded,
      title: 'Live connection',
      subtitle:
          'Updates arrive over a WebSocket and reconnect automatically when '
          'the daemon restarts.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(status: live.status),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  live.status == LiveStatus.live
                      ? 'Receiving live data'
                      : live.status == LiveStatus.disabled
                      ? 'Add a server URL and token to connect.'
                      : live.message ?? 'Connecting to the daemon…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (settings.isConfigured)
                TextButton.icon(
                  onPressed: ref.read(liveControllerProvider.notifier).retry,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Reconnect'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.dns_rounded, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Endpoint: ${settings.normalizedServerUrl}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SettingsSection(
      icon: Icons.info_outline_rounded,
      title: 'About Dockyard',
      subtitle:
          'Desktop client for the Dockyard daemon. Version 0.1.0 · API v1 · '
          'Linux desktop.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'The admin token is stored in this app’s local preferences. '
                'Use a dedicated strong token and keep the daemon on a trusted '
                'network, or put it behind a TLS reverse proxy.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestResult {
  const _TestResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class _TestBanner extends StatelessWidget {
  const _TestBanner({required this.result});

  final _TestResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = result.ok
        ? (theme.brightness == Brightness.dark
              ? Colors.green.shade300
              : Colors.green.shade700)
        : scheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            result.ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
