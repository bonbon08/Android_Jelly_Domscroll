import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'jellyfin_models.dart';

class JellyfinAuthException implements Exception {
  final String message;
  JellyfinAuthException(this.message);
  @override
  String toString() => message;
}

/// Minimal Jellyfin REST client: login, fetch unwatched movies/episodes,
/// and build direct-stream URLs that support HTTP range seeking.
class JellyfinClient {
  static final String _deviceId = const Uuid().v4();
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

  static Map<String, String> _authHeader() => {
        'X-Emby-Authorization':
            'MediaBrowser Client="$_clientName", Device="$_deviceName", '
                'DeviceId="$_deviceId", Version="$_clientVersion"',
      };

  /// Logs in against [serverUrlInput] and returns a session on success.
  static Future<JellyfinSession> login({
    required String serverUrlInput,
    required String username,
    required String password,
  }) async {
    final serverUrl = _normalizeServerUrl(serverUrlInput);
    final uri = Uri.parse('$serverUrl/Users/AuthenticateByName');

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              ..._authHeader(),
              'Content-Type': 'application/json',
            },
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
          'Login fehlgeschlagen (HTTP ${response.statusCode}).$detail');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['AccessToken'] as String?;
    final userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;
    if (token == null || userId == null) {
      throw JellyfinAuthException('Unerwartete Serverantwort.');
    }

    return JellyfinSession(
        serverUrl: serverUrl, accessToken: token, userId: userId);
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
        .replace(queryParameters: {
      'IncludeItemTypes': 'Movie,Episode',
      'Recursive': 'true',
      'Filters': 'IsUnplayed',
      'IsVirtualItem': 'false',
      'SortBy': 'Random',
      'Fields': 'MediaSources,RunTimeTicks,SeriesName,SeriesId',
      'Limit': '$limit',
    });

    final response = await http
        .get(uri, headers: session.authHeaders)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw JellyfinAuthException(
          'Konnte Inhalte nicht laden (HTTP ${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawItems = (data['Items'] as List?) ?? [];
    return rawItems
        .cast<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .where((item) => item.runtime > const Duration(seconds: 30))
        .toList();
  }

  /// Direct-play stream URL. The underlying server supports HTTP range
  /// requests on this endpoint, so the player can seek freely within it.
  static Uri streamUrl(JellyfinSession session, JellyfinItem item) {
    return Uri.parse('${session.serverUrl}/Videos/${item.id}/stream')
        .replace(queryParameters: {
      'Static': 'true',
      if (item.mediaSourceId != null) 'MediaSourceId': item.mediaSourceId,
      'api_key': session.accessToken,
    });
  }
}
