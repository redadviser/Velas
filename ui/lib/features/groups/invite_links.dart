import '../../core/config/env.dart';
import '../../core/i18n/translations.dart';
import '../../data/models/group_models.dart';

/// Links e códigos de convite para grupos.
///
/// * `com.eupasoft.velas://app/join/CODIGO` abre a app diretamente.
/// * `https://<domínio>/g/CODIGO` é o link para partilhar: abre a página de
///   convite servida pelo backend (modules/invitations/invite-page.routes.ts),
///   que tenta abrir a app e, se não estiver instalada, mostra onde a
///   descarregar. O domínio vem de INVITE_BASE_URL (um domínio curto e
///   bonito apontado para a API); sem ele usa-se o da API.
class InviteLinks {
  const InviteLinks._();

  static String appLink(String code) => 'com.eupasoft.velas://app/join/$code';

  static String shareLink(String code) {
    // Sem servidor (modo local) só há o link direto da app.
    final base = (Env.inviteBaseUrl.isNotEmpty ? Env.inviteBaseUrl : Env.apiUrl).replaceFirst(RegExp(r'/+$'), '');
    return base.isEmpty ? appLink(code) : '$base/g/$code';
  }

  /// O link sem `https://`, para mostrar no ecrã.
  static String displayLink(String code) => shareLink(code).replaceFirst(RegExp(r'^https?://'), '');

  /// "K7P2QX9M" → "K7P2 QX9M" (os códigos antigos, de outro tamanho, ficam como estão).
  static String formatCode(String code) => code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

  /// O código como foi escrito ou colado ("k7p2 qx9m", "K7P2-QX9M" ou o link
  /// inteiro), só com letras e números em maiúsculas.
  static String normalizeCode(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    final fromLink = uri != null && uri.hasScheme ? codeFrom(uri) : null;
    return (fromLink ?? text).replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  /// Mensagem para partilhar o link.
  static String linkMessage(GiftGroup g) => tr('Junta-te à prenda em grupo "{title}" na Birthdayly 🎁\n{link}', {
    'title': g.title,
    'link': shareLink(g.inviteCode),
  });

  /// Mensagem para partilhar o código. Nas apps de mensagens não há texto com
  /// link escondido, por isso o link (que já contém o código) vai no fim.
  static String codeMessage(GiftGroup g) => tr(
    'Junta-te à prenda em grupo "{title}" na Birthdayly 🎁\n\n'
    'Código do grupo: {code}\n'
    'Na app: + → Um grupo de prenda → Tenho um código.\n\n'
    'Ou entra diretamente: {link}',
    {'title': g.title, 'code': formatCode(g.inviteCode), 'link': shareLink(g.inviteCode)},
  );

  /// Link para partilhar uma festa surpresa (`/f/CODIGO`): abre a app ou a loja.
  static String partyShareLink(String code) {
    final base = (Env.inviteBaseUrl.isNotEmpty ? Env.inviteBaseUrl : Env.apiUrl).replaceFirst(RegExp(r'/+$'), '');
    return base.isEmpty ? 'com.eupasoft.velas://app/party/$code' : '$base/f/$code';
  }

  /// Código de festa contido num link, se for um convite para uma festa.
  static String? partyCodeFrom(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (uri.scheme == 'com.eupasoft.velas' && uri.host == 'app' && s.length == 2 && s[0] == 'party') return s[1];
    if ((uri.scheme == 'https' || uri.scheme == 'http') && s.length == 2 && s[0] == 'f') return s[1];
    return null;
  }

  /// Código de convite contido num link, se for um link de convite.
  static String? codeFrom(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (uri.scheme == 'com.eupasoft.velas' && uri.host == 'app' && s.length == 2 && s[0] == 'join') return s[1];
    if ((uri.scheme == 'https' || uri.scheme == 'http') && s.length == 2 && s[0] == 'g') return s[1];
    return null;
  }
}
