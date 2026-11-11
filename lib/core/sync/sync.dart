import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart';

/// Started in main() and overridden there.
final syncProvider = Provider<SyncService>(
  (ref) => throw UnimplementedError('syncProvider is overridden in main()'),
);
