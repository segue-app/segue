import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/local_library.dart';
import 'download_manager.dart';

/// Created in main() and overridden there.
final downloadsProvider = Provider<DownloadManager>(
  (ref) =>
      throw UnimplementedError('downloadsProvider is overridden in main()'),
);

final localLibraryProvider = Provider<LocalLibrary>(
  (ref) =>
      throw UnimplementedError('localLibraryProvider is overridden in main()'),
);
