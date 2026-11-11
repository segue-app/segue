import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../library/library_store.dart';
import '../models/track.dart';
import '../player/player_handler.dart';

/// Last.fm scrobbling.
///
/// Last.fm gives API keys per application, so the user enters their own
/// key and secret (last.fm/api/account/create) and signs in once; only the
/// session key is stored, never the password.
class LastFm {
  LastFm(this._library, {http.Client? client})
    : _http = client ?? http.Client() {
    _load();
  }

  final LibraryStore _library;
  final http.Client _http;
  static const _meta = 'lastfm';
  static const _api = 'https://ws.audioscrobbler.com/2.0/';

  String? _key, _secret, _session;

  /// Signed-in user name, or null.
  final user = ValueNotifier<String?>(null);

  void _load() {
    try {
      final j = jsonDecode(_library.getMeta(_meta) ?? '{}') as Map;
      _key = j['key'] as String?;
      _secret = j['secret'] as String?;
      _session = j['session'] as String?;
      user.value = _session == null ? null : j['user'] as String?;
    } catch (_) {}
  }

  /// Last.fm's request signature: md5 of the sorted "name value" pairs
  /// followed by the secret. Exposed for tests.
  static String sign(Map<String, String> params, String secret) {
    final keys = params.keys.toList()..sort();
    final raw = '${keys.map((k) => '$k${params[k]}').join()}$secret';
    return md5.convert(utf8.encode(raw)).toString();
  }

  Future<Map<String, dynamic>> _call(
    Map<String, String> params,
    String key,
    String secret,
  ) async {
    final p = {...params, 'api_key': key};
    final res = await _http
        .post(
          Uri.parse(_api),
          body: {...p, 'api_sig': sign(p, secret), 'format': 'json'},
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (data['error'] != null) throw StateError('${data['message']}');
    return data;
  }

  Future<void> signIn({
    required String apiKey,
    required String secret,
    required String username,
    required String password,
  }) async {
    final data = await _call(
      {
        'method': 'auth.getMobileSession',
        'username': username,
        'password': password,
      },
      apiKey,
      secret,
    );
    final s = data['session'] as Map;
    _key = apiKey;
    _secret = secret;
    _session = s['key'] as String;
    _library.setMeta(
      _meta,
      jsonEncode({
        'key': apiKey,
        'secret': secret,
        'session': _session,
        'user': s['name'],
      }),
    );
    user.value = s['name'] as String?;
  }

  void signOut() {
    _session = null;
    user.value = null;
    _library.setMeta(_meta, '{}');
  }

  Future<void> _send(String method, Track t, {DateTime? startedAt}) async {
    final session = _session;
    if (session == null || _key == null || _secret == null) return;
    try {
      await _call(
        {
          'method': method,
          'artist': t.artist,
          'track': t.title,
          'sk': session,
          if (t.duration != null) 'duration': '${t.duration!.inSeconds}',
          if (startedAt != null)
            'timestamp': '${startedAt.millisecondsSinceEpoch ~/ 1000}',
        },
        _key!,
        _secret!,
      );
    } catch (e) {
      debugPrint('last.fm $method: $e');
    }
  }

  /// Follows the player: "now playing" at the start of a track and a
  /// scrobble once half of it (or four minutes) has actually been heard.
  void attach(SegueAudioHandler player) {
    Track? track;
    var started = DateTime.now();
    var heard = Duration.zero;
    var last = Duration.zero;
    var done = false;
    player.positionStream.listen((pos) {
      final cur = player.current;
      if (cur == null) return;
      if (cur.key != track?.key) {
        track = cur;
        started = DateTime.now();
        heard = Duration.zero;
        last = pos;
        done = false;
        _send('track.updateNowPlaying', cur);
        return;
      }
      // Count only continuous listening, not jumps from seeking.
      final step = pos - last;
      last = pos;
      if (step > Duration.zero && step < const Duration(seconds: 2)) {
        heard += step;
      }
      final total = cur.duration ?? const Duration(minutes: 8);
      if (!done &&
          total > const Duration(seconds: 30) &&
          (heard >= total * 0.5 || heard >= const Duration(minutes: 4))) {
        done = true;
        _send('track.scrobble', cur, startedAt: started);
      }
    });
  }
}

/// Created in main() and overridden there.
final lastFmProvider = Provider<LastFm>(
  (ref) => throw UnimplementedError('lastFmProvider is overridden in main()'),
);
