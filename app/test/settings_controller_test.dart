import 'package:dockyard/core/config/settings.dart';
import 'package:dockyard/core/config/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads, saves, and clears settings', () async {
    SharedPreferences.setMockInitialValues({
      'dockyard.server_url': 'http://192.168.1.20:8080/',
      'dockyard.admin_token': '0123456789abcdef',
    });
    final preferences = await SharedPreferences.getInstance();
    final controller = SettingsController(preferences);
    addTearDown(controller.dispose);

    expect(controller.state.serverUrl, 'http://192.168.1.20:8080/');
    expect(controller.state.isConfigured, isTrue);

    await controller.save(
      const DockyardSettings(
        serverUrl: ' https://dockyard.example.test:8443/// ',
        adminToken: '  fedcba9876543210  ',
      ),
    );

    expect(controller.state.serverUrl, 'https://dockyard.example.test:8443');
    expect(controller.state.adminToken, 'fedcba9876543210');

    final reloaded = SettingsController(preferences);
    addTearDown(reloaded.dispose);
    expect(reloaded.state.serverUrl, controller.state.serverUrl);
    expect(reloaded.state.adminToken, controller.state.adminToken);

    await controller.clearToken();
    expect(controller.state.adminToken, isEmpty);
    expect(controller.state.isConfigured, isFalse);
    expect(preferences.getString('dockyard.admin_token'), isEmpty);
  });
}
