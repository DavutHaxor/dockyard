import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

const _serverUrlKey = 'dockyard.server_url';
const _adminTokenKey = 'dockyard.admin_token';

/// Owns the user-editable connection settings. The app has no login screen:
/// the server URL and admin token are stored here and used to authenticate in
/// the background.
class SettingsController extends StateNotifier<DockyardSettings> {
  SettingsController(this._preferences)
    : super(
        DockyardSettings(
          serverUrl:
              _preferences.getString(_serverUrlKey) ??
              DockyardSettings.defaultServerUrl,
          adminToken: _preferences.getString(_adminTokenKey) ?? '',
        ),
      );

  final SharedPreferences _preferences;

  Future<void> save(DockyardSettings settings) async {
    final next = settings.normalized();
    state = next;
    await Future.wait([
      _preferences.setString(_serverUrlKey, next.serverUrl),
      _preferences.setString(_adminTokenKey, next.adminToken),
    ]);
  }

  Future<void> clearToken() => save(state.copyWith(adminToken: ''));
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, DockyardSettings>(
      (ref) => SettingsController(ref.watch(sharedPreferencesProvider)),
    );
