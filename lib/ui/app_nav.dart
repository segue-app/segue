import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/catalog/deezer.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';

import 'package:segue/core/l10n/l10n.dart';

/// Opens pages inside the current tab from anywhere (track menus, the
/// full-screen player). The shell plugs its navigator in.
abstract final class AppNav {
  static void Function(Route<void> route)? pushInTab;

  static void push(Route<void> route) => pushInTab?.call(route);

  static void album(int id) => push(AlbumScreen.route(id));

  /// Finds the artist by name (the first one of "A, B" / "A & B") on Deezer.
  static Future<void> artistByName(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final artist = await ref.read(catalogProvider).findArtist(name);
      if (artist == null) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Не нашёл исполнителя «{0}»'.trArgs([name]))),
        );
        return;
      }
      push(ArtistScreen.route(artist.id));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Каталог сейчас недоступен'.tr)),
      );
    }
  }
}
