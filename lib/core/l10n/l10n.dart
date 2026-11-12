import 'en.dart';

/// Interface languages. Russian is the language the app is written in:
/// its texts are the keys, and every other language is a table from the
/// Russian text to its own (see en.dart). A text missing from a table
/// falls back to English, then to Russian.
class L10n {
  L10n._();

  /// Code → the language's own name, in the order shown in Settings.
  static const languages = <String, String>{'ru': 'Русский', 'en': 'English'};

  static const _tables = <String, Map<String, String>>{'en': en};

  /// The language in use.
  static String code = 'ru';

  /// Picks the language: [setting] is a code or 'system' (then the
  /// device's language if we have it, English otherwise).
  static void use(String setting, String systemCode) {
    final wanted = setting == 'system' ? systemCode : setting;
    code = languages.containsKey(wanted) ? wanted : 'en';
  }

  static String t(String ru) {
    if (code == 'ru') return ru;
    return _tables[code]?[ru] ?? en[ru] ?? ru;
  }

  /// Russian has three plural forms (1 трек, 2 трека, 5 треков), most
  /// other languages here two: [forms] is "one|few|many" in Russian, and
  /// its translation "one|other" (or however many that language needs,
  /// last one for the rest).
  static String plural(int n, String forms) {
    final f = t(forms).split('|');
    if (code == 'ru') {
      final m10 = n % 10, m100 = n % 100;
      final i = m10 == 1 && m100 != 11
          ? 0
          : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 1 : 2);
      return f[i.clamp(0, f.length - 1)];
    }
    return n == 1 ? f.first : f.last;
  }
}

extension Tr on String {
  /// This (Russian) text in the current language.
  String get tr => L10n.t(this);

  /// The same with {0}, {1}… replaced by [args].
  String trArgs(List<Object?> args) {
    var s = L10n.t(this);
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', '${args[i]}');
    }
    return s;
  }
}
