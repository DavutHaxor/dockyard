class DockyardSettings {
  const DockyardSettings({required this.serverUrl, required this.adminToken});

  static const defaultServerUrl = 'http://127.0.0.1:8080';
  static const minTokenLength = 16;

  final String serverUrl;
  final String adminToken;

  bool get isConfigured =>
      normalizedServerUrl.isNotEmpty && adminToken.trim().isNotEmpty;

  String get normalizedServerUrl {
    var value = serverUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  DockyardSettings normalized() => DockyardSettings(
    serverUrl: normalizedServerUrl,
    adminToken: adminToken.trim(),
  );

  DockyardSettings copyWith({String? serverUrl, String? adminToken}) =>
      DockyardSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        adminToken: adminToken ?? this.adminToken,
      );

  static String? validateServerUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Server URL is required.';

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Use a full URL, for example http://192.168.1.10:8080';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return 'Remove the query string and fragment from the URL.';
    }
    return null;
  }

  static String? validateAdminToken(String? value) {
    final token = value?.trim() ?? '';
    if (token.isEmpty) return 'Admin token is required.';
    if (token.length < minTokenLength) {
      return 'The token must be at least $minTokenLength characters.';
    }
    return null;
  }
}
