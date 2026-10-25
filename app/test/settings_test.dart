import 'package:dockyard/core/config/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DockyardSettings', () {
    test('normalizes trailing slashes and token whitespace', () {
      const settings = DockyardSettings(
        serverUrl: '  http://192.168.1.10:8080///  ',
        adminToken: '  0123456789abcdef  ',
      );

      final normalized = settings.normalized();
      expect(normalized.serverUrl, 'http://192.168.1.10:8080');
      expect(normalized.adminToken, '0123456789abcdef');
      expect(normalized.isConfigured, isTrue);
    });

    test('is not configured without a token', () {
      expect(
        const DockyardSettings(
          serverUrl: 'http://127.0.0.1:8080',
          adminToken: '   ',
        ).isConfigured,
        isFalse,
      );
    });

    test('validates the server URL', () {
      expect(DockyardSettings.validateServerUrl(''), 'Server URL is required.');
      expect(
        DockyardSettings.validateServerUrl('not-a-url'),
        contains('full URL'),
      );
      expect(
        DockyardSettings.validateServerUrl('ftp://example.test'),
        contains('full URL'),
      );
      expect(
        DockyardSettings.validateServerUrl('http://example.test:8080/?a=1'),
        contains('query string'),
      );
      expect(
        DockyardSettings.validateServerUrl('http://example.test:8080/#top'),
        contains('query string'),
      );
      expect(
        DockyardSettings.validateServerUrl('https://dockyard.example.test'),
        isNull,
      );
    });

    test('validates the admin token', () {
      expect(
        DockyardSettings.validateAdminToken(''),
        'Admin token is required.',
      );
      expect(
        DockyardSettings.validateAdminToken('short'),
        contains('at least 16'),
      );
      expect(DockyardSettings.validateAdminToken('0123456789abcdef'), isNull);
    });

    test('copyWith keeps unrelated fields', () {
      const settings = DockyardSettings(
        serverUrl: 'http://example.test:8080',
        adminToken: '0123456789abcdef',
      );

      final cleared = settings.copyWith(adminToken: '');
      expect(cleared.serverUrl, settings.serverUrl);
      expect(cleared.adminToken, isEmpty);
      expect(cleared.isConfigured, isFalse);
    });
  });
}
