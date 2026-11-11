import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import 'music_source.dart';

/// All enabled sources, keyed by kind. Created in main() and overridden there,
/// because the player needs the same instances before the UI starts.
final sourcesProvider = Provider<Map<SourceKind, MusicSource>>(
  (ref) => throw UnimplementedError('sourcesProvider is overridden in main()'),
);

/// Results of one query across every source, filled in as sources answer.
class SearchResults {
  const SearchResults({
    required this.bySource,
    required this.pending,
    required this.failed,
  });

  final Map<SourceKind, List<Track>> bySource;

  /// Sources that have not answered yet.
  final Set<SourceKind> pending;

  /// Sources that failed; the others still show their results.
  final Set<SourceKind> failed;

  bool get done => pending.isEmpty;

  /// Results interleaved across sources (1st of each, then 2nd of each...),
  /// so the best match from every platform is near the top.
  List<Track> merged([SourceKind? only]) {
    if (only != null) return bySource[only] ?? const [];
    final lists = bySource.values.toList();
    final out = <Track>[];
    final longest = lists.fold(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < longest; i++) {
      for (final l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }
}

/// Searches every source in parallel and emits after each one answers.
final searchAllProvider = StreamProvider.autoDispose
    .family<SearchResults, String>((ref, query) {
      final sources = {
        for (final e in ref.read(sourcesProvider).entries)
          if (e.key.searchable) e.key: e.value,
      };
      final bySource = <SourceKind, List<Track>>{};
      final pending = sources.keys.toSet();
      final failed = <SourceKind>{};
      final controller = StreamController<SearchResults>();

      SearchResults snapshot() => SearchResults(
        // Keep a stable source order, whatever answers first.
        bySource: {
          for (final k in sources.keys)
            if (bySource[k] != null) k: bySource[k]!,
        },
        pending: {...pending},
        failed: {...failed},
      );

      controller.add(snapshot());
      for (final source in sources.values) {
        source
            .search(query)
            .timeout(const Duration(seconds: 20))
            .then<void>(
              (tracks) {
                bySource[source.kind] = tracks;
              },
              onError: (Object _) {
                failed.add(source.kind);
              },
            )
            .whenComplete(() {
              pending.remove(source.kind);
              if (controller.isClosed) return;
              controller.add(snapshot());
              if (pending.isEmpty) controller.close();
            });
      }
      ref.onDispose(controller.close);
      return controller.stream;
    });
