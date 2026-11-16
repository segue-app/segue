/// Invitations to a shared playlist or a listening session as ordinary
/// https links: messengers only make http(s) clickable, never segue://.
/// The page (docs/i/index.html) opens Segue with the code, or offers to
/// install it.
class InviteLink {
  InviteLink._();

  static const web = 'https://segue-app.github.io/segue/i/';

  static String playlist(String code) => '$web#p$code';
  static String jam(String code) => '$web#j$code';

  /// The code in a segue:// link or in one of these pages' links, or null
  /// when [input] is neither (then it may be the bare code).
  static String? code(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null) return null;
    if (uri.scheme == 'segue') return uri.queryParameters['c'] ?? '';
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.path.contains('/i')) {
      final f = uri.fragment;
      return f.length > 1 ? f.substring(1) : '';
    }
    return null;
  }
}
