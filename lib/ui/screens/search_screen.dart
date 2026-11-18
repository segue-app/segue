import 'dart:async';

import '../widgets/net_check_sheet.dart';
import '../../core/library/search_history.dart';
import '../widgets/content_width.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artist_screen.dart';
import 'album_screen.dart';
import 'mix_screen.dart';
import 'playlist_screen.dart';
import '../widgets/track_actions.dart';
import '../../core/player/player.dart';

import '../widgets/nav.dart';

import '../widgets/artwork.dart';

import '../../core/catalog/deezer.dart';

import '../../core/models/track.dart';
import '../../core/sources/sources.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../widgets/motion.dart';
import '../widgets/track_tile.dart';

import 'package:segue/core/l10n/l10n.dart';

import '../widgets/h_scroll.dart';
import '../widgets/segue_loader.dart';
import '../widgets/recognize_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  /// Which source to show; null shows everything, merged.
  SourceKind? _filter;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final colors = ref.watch(currentColorsProvider);
    // The shell paints the background; tabs stay transparent over it.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: ContentWidth(
              max: 820,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(22, 22, 22, 14),
                          child: Text(
                            'Поиск'.tr,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _controller,
                            onChanged: _onChanged,
                            onSubmitted: (v) {
                              setState(() => _query = v);
                              ref.read(searchHistoryProvider).addQuery(v);
                            },
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Трек, артист или альбом'.tr,
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: SegueColors.textDim,
                                ),
                              ),
                              // Clear: back to the history at once.
                              // Empty: "Что играет?" (Shazam) instead.
                              suffixIcon: _query.isEmpty
                                  ? IconButton(
                                      tooltip: 'Что играет?'.tr,
                                      icon: const Icon(Icons.mic_rounded),
                                      onPressed: () =>
                                          showRecognizeSheet(context),
                                    )
                                  : IconButton(
                                      tooltip: 'Очистить'.tr,
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () {
                                        _debounce?.cancel();
                                        _controller.clear();
                                        setState(() => _query = '');
                                      },
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Filter appears once there is something to filter.
                        AnimatedSize(
                          duration: SegueMotion.medium,
                          curve: SegueMotion.ease,
                          child: _query.trim().isEmpty
                              ? const SizedBox(width: double.infinity)
                              : _FilterBar(
                                  query: _query.trim(),
                                  filter: _filter,
                                  accent: colors.accent,
                                  labels: {
                                    for (final s in sources.values)
                                      if (s.kind.searchable) s.kind: s.label,
                                  },
                                  onSelect: (f) => setState(() => _filter = f),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: SegueMotion.medium,
                      child: _Results(
                        key: ValueKey('$_filter|$_query'),
                        filter: _filter,
                        query: _query.trim(),
                        onQuery: (q) {
                          _controller.text = q;
                          setState(() => _query = q);
                        },
                        labels: {
                          for (final s in sources.values)
                            if (s.kind.searchable) s.kind: s.label,
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.count,
    this.loading = false,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final int? count;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SegueMotion.medium,
        curve: SegueMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : SegueColors.surfaceHigh,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(19),
        ),
        child: AnimatedDefaultTextStyle(
          duration: SegueMotion.medium,
          style: TextStyle(
            fontFamily: DefaultTextStyle.of(context).style.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? accent : SegueColors.textDim,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (loading) ...[
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: selected ? accent : SegueColors.textDim,
                  ),
                ),
              ] else if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: (selected ? accent : SegueColors.textDim).withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.query,
    required this.filter,
    required this.accent,
    required this.labels,
    required this.onSelect,
  });

  final String query;
  final SourceKind? filter;
  final Color accent;
  final Map<SourceKind, String> labels;
  final ValueChanged<SourceKind?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(searchAllProvider(query)).value;
    return SizedBox(
      height: 38,
      child: HScroll(
        builder: (context, c) => ListView(
          scrollDirection: Axis.horizontal,
          controller: c,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _SourceChip(
              label: 'Все'.tr,
              selected: filter == null,
              accent: accent,
              loading: r == null || !r.done,
              count: r?.merged().length,
              onTap: () => onSelect(null),
            ),
            for (final e in labels.entries)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _SourceChip(
                  label: e.value,
                  selected: filter == e.key,
                  accent: accent,
                  loading: r == null || r.pending.contains(e.key),
                  count: r?.bySource[e.key]?.length,
                  onTap: () => onSelect(e.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    super.key,
    required this.filter,
    required this.query,
    required this.labels,
    this.onQuery,
  });

  final SourceKind? filter;
  final String query;
  final Map<SourceKind, String> labels;

  /// Runs a search again from history.
  final ValueChanged<String>? onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) {
      return _History(onQuery: onQuery ?? (_) {});
    }
    final async = ref.watch(searchAllProvider(query));
    final r = async.value;
    if (r == null) {
      return const Center(child: SegueLoader(size: 40));
    }
    final tracks = r.merged(filter);
    if (tracks.isEmpty) {
      final waiting = filter == null ? !r.done : r.pending.contains(filter);
      if (waiting) {
        return const Center(child: SegueLoader(size: 40));
      }
      final failedHere = filter == null
          ? r.failed.length == labels.length
          : r.failed.contains(filter);
      return _Hint(
        icon: failedHere ? Icons.cloud_off_rounded : Icons.search_off_rounded,
        text: failedHere
            ? 'Источник не отвечает. Возможно, он заблокирован в твоей стране или сети: проверь связь'
                  .tr
            : 'Ничего не нашлось'.tr,
        action: failedHere
            ? TextButton.icon(
                icon: const Icon(Icons.network_check_rounded),
                label: Text('Проверить связь'.tr),
                onPressed: () => showNetCheckSheet(context),
              )
            : null,
      );
    }
    // Artists matching the query on top of the merged list.
    final withArtists = filter == null;
    return WideScroll(
      builder: (context, side) => ListView.builder(
        padding: EdgeInsets.fromLTRB(8 + side, 4, 8 + side, 8),
        itemCount: tracks.length + (withArtists ? 1 : 0),
        itemBuilder: (context, i) {
          if (withArtists && i == 0) return _ArtistRow(query: query);
          final k = withArtists ? i - 1 : i;
          return StaggeredEntrance(
            // Items arriving later (a slower source) shouldn't wait long.
            index: k % 12,
            child: TrackTile(
              tracks: tracks,
              index: k,
              sourceLabel: filter == null ? labels[tracks[k].source] : null,
              onPlayed: () {
                final h = ref.read(searchHistoryProvider);
                h.add(HistoryItem.ofTrack(tracks[k]));
                h.addQuery(query);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists =
        ref.watch(artistSearchProvider(query)).value ?? const <Artist>[];
    // Only artists that really match: the API also returns loose hits.
    final q = query.toLowerCase();
    final shown =
        artists
            .where(
              (a) =>
                  a.fans > 1000 &&
                  (a.name.toLowerCase().contains(q) ||
                      q.contains(a.name.toLowerCase())),
            )
            .toList()
          // The famous one first: many artists share a name.
          ..sort((a, b) => b.fans.compareTo(a.fans));
    final top = shown.take(8).toList();
    return AnimatedSize(
      duration: SegueMotion.medium,
      curve: SegueMotion.ease,
      child: top.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              height: 162,
              child: HScroll(
                builder: (context, c) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  controller: c,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  itemCount: top.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final a = top[i];
                    return PressScale(
                      onTap: () => pushUnique(
                        Navigator.of(context),
                        ArtistScreen.route(a.id),
                      ),
                      child: SizedBox(
                        width: 96,
                        child: Column(
                          children: [
                            ClipOval(
                              child: Artwork(
                                url: a.picture,
                                size: 96,
                                radius: 0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Артист'.tr,
                              style: TextStyle(
                                color: SegueColors.textDim,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 44,
              color: SegueColors.textDim.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SegueColors.textDim, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

/// An empty search: recent searches and what was played or opened, as in
/// Yandex Music. Each can be removed; "Очистить" forgets everything.
class _History extends ConsumerWidget {
  const _History({required this.onQuery});

  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.read(searchHistoryProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([h.items, h.queries]),
      builder: (context, _) {
        final items = h.items.value, queries = h.queries.value;
        if (items.isEmpty && queries.isEmpty) {
          return _Hint(
            icon: Icons.graphic_eq_rounded,
            text: 'Найди что-нибудь — YouTube и SoundCloud в одном месте'.tr,
          );
        }
        final songs = [
          for (final i in items)
            if (i.track != null) i.track!,
        ];
        return WideScroll(
          builder: (context, side) => ListView(
            padding: EdgeInsets.fromLTRB(8 + side, 0, 8 + side, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                child: Row(
                  children: [
                    Text(
                      'Вы искали'.tr,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    TextButton(onPressed: h.clear, child: Text('Очистить'.tr)),
                  ],
                ),
              ),
              if (queries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final q in queries)
                        InputChip(
                          avatar: const Icon(Icons.history_rounded, size: 18),
                          label: Text(q),
                          onPressed: () => onQuery(q),
                          onDeleted: () => h.removeQuery(q),
                          deleteIconColor: SegueColors.textDim,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                    ],
                  ),
                ),
              for (final i in items)
                _HistoryTile(
                  item: i,
                  onTap: () => _open(context, ref, i, songs),
                  onRemove: () => h.remove(i),
                ),
            ],
          ),
        );
      },
    );
  }

  void _open(
    BuildContext context,
    WidgetRef ref,
    HistoryItem i,
    List<Track> songs,
  ) {
    final nav = Navigator.of(context);
    final id = int.tryParse(i.id);
    switch (i.kind) {
      case HistoryKind.track:
        // The songs of the history play one after another.
        final at = songs.indexWhere((t) => t.key == i.id);
        ref.read(playerProvider).tapTrack(songs, at < 0 ? 0 : at);
        ref.read(searchHistoryProvider).add(i);
      case HistoryKind.artist:
        if (id != null) pushUnique(nav, ArtistScreen.route(id));
      case HistoryKind.album:
        if (id != null) nav.push(AlbumScreen.route(id));
      case HistoryKind.mix:
        if (id != null) nav.push(MixScreen.route(id));
      case HistoryKind.playlist:
        nav.push(PlaylistScreen.route(i.id));
    }
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final HistoryItem item;
  final VoidCallback onTap, onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = switch (item.kind) {
      HistoryKind.track => 'Трек'.tr,
      HistoryKind.artist => 'Артист'.tr,
      HistoryKind.album => 'Альбом'.tr,
      HistoryKind.mix => 'Подборка'.tr,
      HistoryKind.playlist => 'Плейлист'.tr,
    };
    final sub = item.kind == HistoryKind.track || item.kind == HistoryKind.album
        ? '$kind · ${item.subtitle}'
        : kind;
    final round = item.kind == HistoryKind.artist;
    return PressScale(
      scale: 0.98,
      hoverRadius: 16,
      onTap: onTap,
      onLongPress: item.track == null
          ? null
          : () => showTrackActions(context, ref, item.track!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            round
                ? ClipOval(child: Artwork(url: item.image, size: 52, radius: 0))
                : Artwork(url: item.image, size: 52, radius: 10),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SegueColors.textDim,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Убрать из истории'.tr,
              icon: const Icon(Icons.close_rounded, size: 20),
              color: SegueColors.textDim,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
