import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playlist_importer.dart';

/// Created in main() and overridden there (it needs SoundCloud's client id).
final importerProvider = Provider<PlaylistImporter>(
  (ref) => PlaylistImporter(),
);
