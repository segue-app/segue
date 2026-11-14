import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';

/// Asks before something that can't be undone; true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? action,
}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text('Отмена'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(action ?? 'Удалить'.tr),
          ),
        ],
      ),
    ) ??
    false;
