/// Configuração injetada em tempo de compilação:
///
///   flutter run --dart-define=API_URL=http://localhost:3000 \
///               --dart-define=GOOGLE_SERVER_CLIENT_ID=123-abc.apps.googleusercontent.com
///
/// Sem API_URL a app usa a API de produção. Com `--dart-define=API_URL=`
/// (vazio) arranca em "modo local": os dados ficam apenas no dispositivo, o que
/// é útil para desenvolvimento.
class Env {
  const Env._();

  /// Endereço da API (pasta `backend`), sem barra final.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://velas-backend.triplanai.eupasoft.com');

  /// Client ID OAuth do tipo "Web application" do projeto Google Cloud.
  /// O Android precisa dele para devolver o ID token que a API valida.
  /// No iOS o client ID está no Info.plist (ver ios/Flutter/Google.xcconfig).
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Domínio dos links de convite (`<domínio>/g/CODIGO`), se for diferente da
  /// API, por exemplo um domínio curto que redireciona para ela. Por omissão
  /// usa-se o API_URL, que já serve a página de convite.
  static const inviteBaseUrl = String.fromEnvironment('INVITE_BASE_URL');

  static bool get hasBackend => apiUrl.isNotEmpty;

  /// Login com Google e importação do Google Contacts.
  static bool get hasGoogle => googleServerClientId.isNotEmpty;
}
