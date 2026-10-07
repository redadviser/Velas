import '../../core/config/env.dart';
import '../../data/models/group_models.dart';

/// Links de convite para grupos.
///
/// * `com.eupasoft.velas://app/join/CODIGO` abre a app diretamente.
/// * `https://<API>/g/CODIGO` é o link para partilhar: abre a página de
///   convite servida pelo backend (modules/invitations/invite-page.routes.ts),
///   que tenta abrir a app e, se não estiver instalada, mostra onde a
///   descarregar. INVITE_BASE_URL permite usar outro domínio.
class InviteLinks {
  const InviteLinks._();

  static String appLink(String code) => 'com.eupasoft.velas://app/join/$code';

  static String shareLink(String code) {
    // Sem servidor (modo local) só há o link direto da app.
    final base = (Env.inviteBaseUrl.isNotEmpty ? Env.inviteBaseUrl : Env.apiUrl).replaceFirst(RegExp(r'/+$'), '');
    return base.isEmpty ? appLink(code) : '$base/g/$code';
  }

  static String shareText(GiftGroup g) =>
      'Junta-te à prenda em grupo "${g.title}" na app Velas 🎁\n${shareLink(g.inviteCode)}\n\n'
      'Ou abre Presentes → Em grupo → "Tenho um código" e usa ${g.inviteCode}.';

  /// Código de convite contido num link, se for um link de convite.
  static String? codeFrom(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (uri.scheme == 'com.eupasoft.velas' && uri.host == 'app' && s.length == 2 && s[0] == 'join') return s[1];
    if (uri.scheme == 'https' && s.length == 2 && s[0] == 'g') return s[1];
    return null;
  }
}
