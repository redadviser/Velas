import 'dart:async';
import 'dart:io';

import '../../data/api/api_client.dart';
import '../i18n/translations.dart';

/// Erro com uma mensagem já pronta a mostrar ao utilizador.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// O código não é de nenhum grupo nem festa.
const invalidInviteCode = AppException('Código inválido. Confirma com quem te convidou.');

/// Interrompe uma ação cujo erro já está visível (ex.: no próprio campo).
class SilentException implements Exception {
  const SilentException();
}

/// Converte qualquer erro numa frase compreensível (RNF09).
String friendlyError(Object error) {
  if (error is AppException) return tr(error.message);
  if (error is SocketException || error is TimeoutException || error is HandshakeException) {
    return tr('Sem ligação à internet. Verifica a tua rede e tenta novamente.');
  }
  if (error is ApiException) return _apiError(error);
  final text = error.toString();
  if (text.contains('ClientException') || text.contains('SocketException')) {
    return tr('Sem ligação à internet. Verifica a tua rede e tenta novamente.');
  }
  return tr('Ocorreu um erro inesperado. Tenta novamente.');
}

String _apiError(ApiException e) => switch (e.code) {
  'invalid_credentials' => tr('Email, username ou palavra-passe incorretos.'),
  'google_account' => tr('Esta conta foi criada com o Google. Usa "Continuar com Google".'),
  'email_taken' => tr('Já existe uma conta com este email.'),
  'username_taken' => tr('Este username já está a ser usado.'),
  'phone_taken' => tr('Este telemóvel já está associado a outra conta.'),
  'rate_limited' => tr('Demasiadas tentativas. Aguarda um pouco e tenta novamente.'),
  'session_expired' ||
  'invalid_refresh_token' ||
  'unauthorized' => tr('A tua sessão expirou. Inicia sessão novamente.'),
  'invalid_reset_token' => tr('Este link já foi usado ou expirou. Pede um novo email de recuperação.'),
  'google_not_configured' => tr('O login com Google ainda não está disponível.'),
  'invalid_google_token' => tr('Não foi possível validar a conta Google. Tenta novamente.'),
  'plus_required' => tr('Isto faz parte do Birthdayly+. Vê os planos no Perfil.'),
  'friend_already_linked' => tr('Este amigo já está ligado a outro aniversário.'),
  'forbidden' when e.message == 'not_friends' => tr('Só podes ligar o aniversário a um amigo da Birthdayly.'),
  'forbidden' => tr('Não tens permissão para realizar esta ação.'),
  'not_found' => tr('Este registo já não existe. Atualiza e tenta novamente.'),
  'validation_error' || 'invalid_value' || 'invalid_reference' => tr('Há um valor inválido. Confirma os dados.'),
  'too_large' || 'unsupported_media_type' => tr('Não foi possível carregar a fotografia.'),
  'storage_unavailable' => tr('O servidor não conseguiu guardar a imagem. Tenta novamente daqui a pouco.'),
  _ when e.status >= 500 => tr('O servidor está indisponível. Tenta novamente daqui a pouco.'),
  _ => tr('Não foi possível guardar as alterações. Tenta novamente.'),
};
