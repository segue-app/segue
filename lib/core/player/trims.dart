import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart';
import '../library/library_store.dart';
import '../models/track.dart';

/// Where a track should start and stop (skipping a long intro, a talky
/// outro, a music video's skit…). Either end can be open.
@immutable
class Trim {
  const Trim({this.start, this.end});

  final Duration? start;
  final Duration? end;

  bool get isEmpty => start == null && end == null;

  Map<String, int?> toJson() => {
    'start': start?.inMilliseconds,
    'end': end?.inMilliseconds,
  };

  factory Trim.fromJson(Map j) => Trim(
    start: j['start'] == null
        ? null
        : Duration(milliseconds: j['start'] as int),
    end: j['end'] == null ? null : Duration(milliseconds: j['end'] as int),
  );
}

/// Trims by track key, kept on this device.
class TrimStore {
  TrimStore(this._library) {
    try {
      final j = jsonDecode(_library.getMeta(_key) ?? '{}') as Map;
      for (final e in j.entries) {
        _trims[e.key as String] = Trim.fromJson(e.value as Map);
      }
    } catch (_) {}
  }

  static const _key = 'trims';
  final LibraryStore _library;
  final _trims = <String, Trim>{};

  /// Bumps on every change, for the UI.
  final version = ValueNotifier(0);

  Trim? of(Track t) => _trims[t.key];

  void set(Track t, Trim? trim) {
    if (trim == null || trim.isEmpty) {
      _trims.remove(t.key);
    } else {
      _trims[t.key] = trim;
    }
    _library.setMeta(
      _key,
      jsonEncode({for (final e in _trims.entries) e.key: e.value.toJson()}),
    );
    version.value++;
  }
}

final trimStoreProvider = Provider<TrimStore>(
  (ref) => TrimStore(ref.read(libraryProvider)),
);
