import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../player/player_handler.dart';

/// Keeps the Android home-screen widget (SegueWidgetProvider.kt) showing
/// what plays: title, artist, play/pause state and the cover.
class HomeWidgets {
  HomeWidgets(this.player);

  final SegueAudioHandler player;
  static bool get supported => Platform.isAndroid;

  Timer? _debounce;
  String? _coverUrl;
  String? _coverPath;

  void attach() {
    if (!supported) return;
    player.mediaItem.listen((_) => _schedule());
    player.stateChanges.listen((_) => _schedule());
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _push);
  }

  Future<void> _push() async {
    final item = player.mediaItem.value;
    try {
      await HomeWidget.saveWidgetData<String>('title', item?.title);
      await HomeWidget.saveWidgetData<String>('artist', item?.artist);
      await HomeWidget.saveWidgetData<bool>(
        'playing',
        player.playbackState.value.playing,
      );
      await HomeWidget.saveWidgetData<String>(
        'cover',
        await _cover(item?.artUri),
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'fm.segue.segue.SegueWidgetProvider',
      );
    } catch (e) {
      debugPrint('widget: $e');
    }
  }

  /// A local file with the cover (widgets can't load URLs themselves).
  Future<String?> _cover(Uri? art) async {
    if (art == null) return null;
    if (art.isScheme('file')) return art.toFilePath();
    final url = art.toString();
    if (url == _coverUrl) return _coverPath;
    try {
      final res = await http.get(art).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _coverPath;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/widget_cover.jpg');
      await file.writeAsBytes(res.bodyBytes, flush: true);
      _coverUrl = url;
      _coverPath = file.path;
    } catch (_) {}
    return _coverPath;
  }
}
