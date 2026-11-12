import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// This build's version; keep in step with pubspec.yaml.
const appVersion = '0.3.4';

/// GitHub repository releases are published in.
const appRepo = 'segue-app/segue';

class AppUpdate {
  const AppUpdate(this.version, this.url, this.notes, {this.assets = const {}});
  final String version;
  final String url;
  final String notes;

  /// Release files by name (segue-macos.zip…) → download URL.
  final Map<String, String> assets;
}

/// True when version [a] is newer than [b] ("1.2.10" > "1.2.9").
bool isNewer(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.replaceFirst(RegExp('^v'), '').split('.'))
      int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final m = i < x.length ? x[i] : 0, n = i < y.length ? y[i] : 0;
    if (m != n) return m > n;
  }
  return false;
}

/// The latest GitHub release if it is newer than this build, else null.
Future<AppUpdate?> checkForUpdate({http.Client? client}) =>
    checkForUpdateFrom(appVersion, client: client);

/// The latest release if it is newer than [current].
Future<AppUpdate?> checkForUpdateFrom(
  String current, {
  http.Client? client,
}) async {
  final res = await (client ?? http.Client())
      .get(
        Uri.parse('https://api.github.com/repos/$appRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) return null;
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final tag = j['tag_name'] as String? ?? '';
  if (!isNewer(tag, current)) return null;
  return AppUpdate(
    tag.replaceFirst(RegExp('^v'), ''),
    j['html_url'] as String? ?? 'https://github.com/$appRepo/releases',
    j['body'] as String? ?? '',
    assets: {
      for (final a in (j['assets'] as List? ?? const []))
        if ((a as Map)['name'] is String && a['browser_download_url'] is String)
          a['name'] as String: a['browser_download_url'] as String,
    },
  );
}

final updateProvider = FutureProvider<AppUpdate?>(
  (ref) => checkForUpdate().catchError((Object _) => null),
);
