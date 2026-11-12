import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/l10n/en.dart';
import 'package:segue/core/l10n/l10n.dart';

void main() {
  test('every text marked for translation has an English one', () {
    final marked = RegExp(r"'((?:[^'\\\n]|\\.)*)'\s*\.\s*(?:tr\b|trArgs\()");
    final plural = RegExp(r"L10n\.plural\([^,]+,\s*'((?:[^'\\\n]|\\.)*)'");
    final cyrillic = RegExp('[А-Яа-яЁё]');
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in [...marked.allMatches(src), ...plural.allMatches(src)]) {
        // As Dart reads the literal.
        final key = m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\n', '\n');
        if (cyrillic.hasMatch(key) && !en.containsKey(key)) missing.add(key);
      }
    }
    expect(missing, isEmpty);
  });

  test('placeholders survive translation', () {
    final ph = RegExp(r'\{\d\}');
    for (final e in en.entries) {
      Set<String> of(String s) => {for (final m in ph.allMatches(s)) m.group(0)!};
      expect(of(e.value), of(e.key), reason: e.key);
    }
  });

  test('language choice, fallback and plurals', () {
    L10n.use('system', 'de'); // not available: English
    expect(L10n.code, 'en');
    expect('Поиск'.tr, 'Search');
    expect('Вышла версия {0}'.trArgs(['1.2']), 'Version 1.2 is out');
    expect('Текст без перевода'.tr, 'Текст без перевода');
    expect(L10n.plural(1, 'трек|трека|треков'), 'track');
    expect(L10n.plural(21, 'трек|трека|треков'), 'tracks');
    L10n.use('system', 'ru');
    expect('Поиск'.tr, 'Поиск');
    expect(L10n.plural(21, 'трек|трека|треков'), 'трек');
    expect(L10n.plural(3, 'трек|трека|треков'), 'трека');
    expect(L10n.plural(11, 'трек|трека|треков'), 'треков');
  });
}
