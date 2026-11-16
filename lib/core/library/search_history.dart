import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import 'library.dart';
import 'library_store.dart';

/// What a history entry opens.
enum HistoryKind { track, artist, album, mix, playlist }

/// Something found or opened: shown under an empty search field.
@immutable
class HistoryItem {
  const HistoryItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.image,
    this.track,
  });

  final HistoryKind kind;

  /// Deezer id (artist, album, mix), playlist id or track key.
  final String id;
  final String title;
  final String subtitle;
  final String? image;

  /// For a song: the song itself, to play it again.
  final Track? track;

  String get key => '${kind.name}:$id';

  Map<String, dynamic> toJson() => {
    'k': kind.name,
    'id': id,
    't': title,
    's': subtitle,
    'i': ?image,
    if (track != null) 'tr': track!.toJson(),
  };

  static HistoryItem? fromJson(Map<String, dynamic> j) {
    final kind = HistoryKind.values.asNameMap()[j['k']];
    if (kind == null) return null;
    final tr = j['tr'];
    return HistoryItem(
      kind: kind,
      id: j['id'] as String? ?? '',
      title: j['t'] as String? ?? '',
      subtitle: j['s'] as String? ?? '',
      image: j['i'] as String?,
      track: tr is Map ? Track.fromJson(tr.cast<String, dynamic>()) : null,
    );
  }

  factory HistoryItem.ofTrack(Track t) => HistoryItem(
    kind: HistoryKind.track,
    id: t.key,
    title: t.displayTitle,
    subtitle: t.artist,
    image: t.artworkUrl,
    track: t,
  );
}

/// Recent searches and what was opened or played from them, newest first,
/// as in Yandex Music. Kept on this device only.
class SearchHistory {
  SearchHistory(this._store) {
    try {
      final j = jsonDecode(_store.getMeta(_itemsKey) ?? '[]') as List;
      items.value = [
        for (final e in j)
          if (e is Map) ?HistoryItem.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {}
    try {
      queries.value = [
        for (final q in jsonDecode(_store.getMeta(_queriesKey) ?? '[]') as List)
          '$q',
      ];
    } catch (_) {}
  }

  final LibraryStore _store;
  static const _itemsKey = 'search_history', _queriesKey = 'search_queries';
  static const maxItems = 40, maxQueries = 12;

  final items = ValueNotifier<List<HistoryItem>>(const []);
  final queries = ValueNotifier<List<String>>(const []);

  void add(HistoryItem item) {
    if (item.id.isEmpty || item.title.isEmpty) return;
    items.value = [
      item,
      ...items.value.where((e) => e.key != item.key),
    ].take(maxItems).toList();
    _saveItems();
  }

  void remove(HistoryItem item) {
    items.value = [...items.value.where((e) => e.key != item.key)];
    _saveItems();
  }

  void addQuery(String q) {
    final s = q.trim();
    if (s.length < 2) return;
    queries.value = [
      s,
      ...queries.value.where((e) => e.toLowerCase() != s.toLowerCase()),
    ].take(maxQueries).toList();
    _store.setMeta(_queriesKey, jsonEncode(queries.value));
  }

  void removeQuery(String q) {
    queries.value = [...queries.value.where((e) => e != q)];
    _store.setMeta(_queriesKey, jsonEncode(queries.value));
  }

  void clear() {
    items.value = const [];
    queries.value = const [];
    _saveItems();
    _store.setMeta(_queriesKey, '[]');
  }

  void _saveItems() => _store.setMeta(
    _itemsKey,
    jsonEncode([for (final e in items.value) e.toJson()]),
  );
}

final searchHistoryProvider = Provider<SearchHistory>(
  (ref) => SearchHistory(ref.read(libraryProvider)),
);

/// Remembers [item] after this frame (screens call it while building).
void rememberOpened(WidgetRef ref, HistoryItem item) {
  final h = ref.read(searchHistoryProvider);
  if (h.items.value.firstOrNull?.key == item.key) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => h.add(item));
}
