import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artist_screen.dart';

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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
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
                        onSubmitted: (v) => setState(() => _query = v),
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
                    const SizedBox(height: 8),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: SegueMotion.medium,
                        child: _Results(
                          key: ValueKey('$_filter|$_query'),
                          filter: _filter,
                          query: _query.trim(),
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
      child: ListView(
        scrollDirection: Axis.horizontal,
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
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    super.key,
    required this.filter,
    required this.query,
    required this.labels,
  });

  final SourceKind? filter;
  final String query;
  final Map<SourceKind, String> labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) {
      return _Hint(
        icon: Icons.graphic_eq_rounded,
        text: 'Найди что-нибудь — YouTube и SoundCloud в одном месте'.tr,
      );
    }
    final async = ref.watch(searchAllProvider(query));
    final r = async.value;
    if (r == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            strokeCap: StrokeCap.round,
          ),
        ),
      );
    }
    final tracks = r.merged(filter);
    if (tracks.isEmpty) {
      final waiting = filter == null ? !r.done : r.pending.contains(filter);
      if (waiting) {
        return const Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
            ),
          ),
        );
      }
      final failedHere = filter == null
          ? r.failed.length == labels.length
          : r.failed.contains(filter);
      return _Hint(
        icon: failedHere ? Icons.cloud_off_rounded : Icons.search_off_rounded,
        text: failedHere
            ? 'Источник сейчас не отвечает. Попробуй ещё раз чуть позже.'.tr
            : 'Ничего не нашлось'.tr,
      );
    }
    // Artists matching the query on top of the merged list.
    final withArtists = filter == null;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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
          ),
        );
      },
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
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
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
                            child: Artwork(url: a.picture, size: 96, radius: 0),
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
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

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
          ],
        ),
      ),
    );
  }
}
