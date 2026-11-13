import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/library/library.dart';
import '../widgets/collection.dart';
import '../widgets/track_actions.dart';

/// Name, description, icon and colours of each smart playlist.
({String title, String subtitle, IconData icon, List<Color> gradient})
smartInfo(SmartList kind) => switch (kind) {
  SmartList.onRepeat => (
    title: 'Часто слушаю'.tr,
    subtitle: 'Что играло больше всего за месяц'.tr,
    icon: Icons.repeat_rounded,
    gradient: const [Color(0xFFFF8A5B), Color(0xFFE0457B)],
  ),
  SmartList.forgotten => (
    title: 'Давно не включал'.tr,
    subtitle: 'Любимое, что не звучало полтора месяца'.tr,
    icon: Icons.history_rounded,
    gradient: const [Color(0xFF5B8CFF), Color(0xFF7B5CFF)],
  ),
  SmartList.newLikes => (
    title: 'Лайки за месяц'.tr,
    subtitle: 'Всё, что понравилось за последние 30 дней'.tr,
    icon: Icons.auto_awesome_rounded,
    gradient: const [Color(0xFF3CCB9A), Color(0xFF2A9BD8)],
  ),
};

/// A smart playlist: it fills (and updates) itself from your listening.
class SmartPlaylistScreen extends ConsumerWidget {
  const SmartPlaylistScreen({super.key, required this.kind});

  final SmartList kind;

  static Route<void> route(SmartList kind) => MaterialPageRoute(
    settings: RouteSettings(name: '/smart/${kind.name}'),
    builder: (_) => SmartPlaylistScreen(kind: kind),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(smartTracksProvider(kind));
    final info = smartInfo(kind);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: TrackCollectionView(
        title: info.title,
        subtitle: '${info.subtitle} · ${tracksLabel(tracks.length)}',
        tracks: tracks,
        playContext: 'smart:${kind.name}',
        emptyText: 'Послушай побольше, и здесь появится подборка'.tr,
        cover: CoverCollage(
          urls: const [],
          size: MediaQuery.sizeOf(context).width > 600 ? 200.0 : 180.0,
          icon: info.icon,
          gradient: LinearGradient(colors: info.gradient),
        ),
      ),
    );
  }
}
