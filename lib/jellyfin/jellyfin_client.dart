import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'jellyfin_models.dart';
import 'session_store.dart';

class JellyfinAuthException implements Exception {
  final String message;
  JellyfinAuthException(this.message);
  @override
  String toString() => message;
}

/// Minimal Jellyfin REST client: login/logout and fetching unwatched
/// movies/episodes. Video streams go through [StreamProxy].
class JellyfinClient {
  static const String _clientName = 'JellyReels';
  static const String _deviceName = 'JellyReels Client';
  static const String _clientVersion = '1.0.0';

  static String _normalizeServerUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  // A stable device id makes Jellyfin replace this device's previous token
  // on re-login instead of piling up still-valid tokens.
  static Future<Map<String, String>> _authHeader() async {
    final deviceId = await SessionStore.deviceId(() => const Uuid().v4());
    return {
      'X-Emby-Authorization':
          'MediaBrowser Client="$_clientName", Device="$_deviceName", '
          'DeviceId="$deviceId", Version="$_clientVersion"',
    };
  }

  /// Logs in against [serverUrlInput] and returns a session on success.
  static Future<JellyfinSession> login({
    required String serverUrlInput,
    required String username,
    required String password,
  }) async {
    final serverUrl = _normalizeServerUrl(serverUrlInput);
    final uri = Uri.tryParse('$serverUrl/Users/AuthenticateByName');
    if (uri == null || uri.host.isEmpty) {
      throw JellyfinAuthException('Ungültige Server-Adresse.');
    }

    final authHeader = await _authHeader();
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {...authHeader, 'Content-Type': 'application/json'},
            body: jsonEncode({'Username': username, 'Pw': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw JellyfinAuthException('Server nicht erreichbar: $e');
    }

    if (response.statusCode == 401) {
      throw JellyfinAuthException('Benutzername oder Passwort falsch.');
    }
    if (response.statusCode != 200) {
      final bodySnippet = response.body.trim();
      final detail = bodySnippet.isNotEmpty
          ? '\n${bodySnippet.substring(0, bodySnippet.length > 300 ? 300 : bodySnippet.length)}'
          : '';
      throw JellyfinAuthException(
        'Login fehlgeschlagen (HTTP ${response.statusCode}).$detail',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['AccessToken'] as String?;
    final userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;
    if (token == null || userId == null) {
      throw JellyfinAuthException('Unerwartete Serverantwort.');
    }

    return JellyfinSession(
      serverUrl: serverUrl,
      accessToken: token,
      userId: userId,
    );
  }

  /// Validates that a stored session's token is still valid.
  static Future<bool> validateSession(JellyfinSession session) async {
    try {
      final uri = Uri.parse('${session.serverUrl}/Users/Me');
      final response = await http
          .get(uri, headers: session.authHeaders)
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches a batch of not-yet-watched movies and episodes, in random order.
  static Future<List<JellyfinItem>> fetchUnwatched(
    JellyfinSession session, {
    int limit = 60,
  }) async {
    final uri = Uri.parse('${session.serverUrl}/Users/${session.userId}/Items')
        .replace(
          queryParameters: {
            'IncludeItemTypes': 'Movie,Episode',
            'Recursive': 'true',
            'Filters': 'IsUnplayed',
            'IsVirtualItem': 'false',
            'SortBy': 'Random',
            'Fields': 'MediaSources,RunTimeTicks,SeriesName,SeriesId',
            'Limit': '$limit',
          },
        );

    final response = await http
        .get(uri, headers: session.authHeaders)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw JellyfinAuthException(
        'Konnte Inhalte nicht laden (HTTP ${response.statusCode}).',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawItems = (data['Items'] as List?) ?? [];
    return rawItems
        .cast<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .where((item) => item.runtime > const Duration(seconds: 30))
        .toList();
  }

  /// Revokes the token on the server; clearing it locally alone would leave
  /// it valid for anyone who copied it.
  static Future<void> logout(JellyfinSession session) async {
    try {
      await http
          .post(
            Uri.parse('${session.serverUrl}/Sessions/Logout'),
            headers: session.authHeaders,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline: the local session is still cleared by the caller.
    }
  }

  /// True when [serverUrlInput] would send the password and token
  /// unencrypted to a host outside the local network.
  static bool isInsecureRemote(String serverUrlInput) {
    final uri = Uri.tryParse(_normalizeServerUrl(serverUrlInput));
    if (uri == null || uri.scheme != 'http') return false;
    return !_isLocalHost(uri.host);
  }

  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' ||
        h.endsWith('.local') ||
        h.endsWith('.lan') ||
        h.endsWith('.home.arpa') ||
        !h.contains('.') && !h.contains(':')) {
      return true;
    }
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          // CGNAT range, used by Tailscale whose tunnel is encrypted.
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    return (b[0] & 0xfe) == 0xfc;
  }
}
