import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'jellyfin_models.dart';

/// Loopback-only HTTP proxy between the native media libraries (mpv, ffmpeg)
/// and Jellyfin. The access token is added here as a header, so it never
/// appears in a URL handed to native code — where it would end up in logs,
/// in ffmpeg's command line (readable by every local user via /proc), and
/// in TLS connections that mpv/ffmpeg do not certificate-verify by default.
/// The upstream connection uses Dart's HttpClient, which does verify.
///
/// Only `GET`/`HEAD` of a single item's direct stream is forwarded, and only
/// under a random per-session path secret, so other local apps can't use the
/// port to reach the server with the user's credentials.
class StreamProxy {
  final JellyfinSession _session;
  final HttpServer _server;
  final String _secret;
  final HttpClient _client;

  static final _idPattern = RegExp(r'^[0-9a-fA-F]{32}$|^[0-9a-fA-F-]{36}$');

  StreamProxy._(this._session, this._server, this._secret, this._client) {
    _server.listen(_handle);
  }

  static Future<StreamProxy> start(JellyfinSession session) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final rnd = Random.secure();
    final secret = List.generate(
      32,
      (_) => rnd.nextInt(16).toRadixString(16),
    ).join();
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15);
    return StreamProxy._(session, server, secret, client);
  }

  Uri streamUrl(JellyfinItem item) => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    pathSegments: [_secret, item.id],
    queryParameters: item.mediaSourceId != null
        ? {'MediaSourceId': item.mediaSourceId}
        : null,
  );

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segments = req.uri.pathSegments;
      final mediaSourceId = req.uri.queryParameters['MediaSourceId'];
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
        await res.close();
        return;
      }
      if (segments.length != 2 ||
          !_constantTimeEquals(segments[0], _secret) ||
          !_idPattern.hasMatch(segments[1]) ||
          (mediaSourceId != null && !_idPattern.hasMatch(mediaSourceId))) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }

      final upstreamUri =
          Uri.parse('${_session.serverUrl}/Videos/${segments[1]}/stream')
              .replace(
                queryParameters: {
                  'Static': 'true',
                  'MediaSourceId': ?mediaSourceId,
                },
              );
      final upReq = await _client.openUrl(req.method, upstreamUri);
      // A redirect would carry the token header to wherever it points.
      upReq.followRedirects = false;
      upReq.headers.set('X-Emby-Token', _session.accessToken);
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) upReq.headers.set(HttpHeaders.rangeHeader, range);
      final upRes = await upReq.close();

      res.statusCode = upRes.statusCode;
      for (final name in const [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.lastModifiedHeader,
        HttpHeaders.etagHeader,
      ]) {
        final value = upRes.headers.value(name);
        if (value != null) res.headers.set(name, value);
      }
      if (upRes.contentLength >= 0) {
        res.contentLength = upRes.contentLength;
      }
      await upRes.pipe(res);
    } catch (_) {
      // Players drop connections on every seek; that surfaces here as a
      // broken pipe and needs no handling beyond closing our side.
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> close() async {
    await _server.close(force: true);
    _client.close(force: true);
  }
}
