import '../../core/config/env.dart';

/// Links dos cartões de parabéns.
///
/// * `https://<domínio>/c/TOKEN` é o link para partilhar: abre a página do
///   cartão servida pelo backend (modules/cards/card-page.routes.ts), que
///   mostra a mensagem a quem ainda não tem a app.
/// * `com.eupasoft.velas://app/card/TOKEN` abre a app diretamente.
class CardLinks {
  const CardLinks._();

  static final _token = RegExp(r'^[A-Za-z0-9_-]{22}$');

  static String shareLink(String token) {
    final base = (Env.inviteBaseUrl.isNotEmpty ? Env.inviteBaseUrl : Env.apiUrl).replaceFirst(RegExp(r'/+$'), '');
    return '$base/c/$token';
  }

  /// Texto para o WhatsApp: não revela a mensagem, para a pessoa abrir o cartão.
  static String shareMessage(String recipientName, String token) =>
      'Parabéns, $recipientName! 🎂 Deixei-te uma mensagem especial: ${shareLink(token)}';

  /// Token de um link de cartão (da app ou da página), se for um.
  static String? tokenFrom(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    String? token;
    if (uri.scheme == 'com.eupasoft.velas' && uri.host == 'app' && s.length == 2 && s[0] == 'card') token = s[1];
    if ((uri.scheme == 'https' || uri.scheme == 'http') && s.length == 2 && s[0] == 'c') token = s[1];
    return token != null && _token.hasMatch(token) ? token : null;
  }

  /// Token num texto: o link copiado pela página no iPhone.
  static String? tokenFromText(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri == null ? null : tokenFrom(uri);
  }

  /// Token no referrer da Play Store (`card=TOKEN`).
  static String? tokenFromReferrer(String referrer) {
    final token = Uri.splitQueryString(referrer)['card'];
    return token != null && _token.hasMatch(token) ? token : null;
  }
}
