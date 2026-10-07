import 'dart:async';
import 'dart:io';

import '../../data/api/api_client.dart';

/// Erro com uma mensagem já pronta a mostrar ao utilizador.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Interrompe uma ação cujo erro já está visível (ex.: no próprio campo).
class SilentException implements Exception {
  const SilentException();
}

/// Converte qualquer erro numa frase compreensível (RNF09).
String friendlyError(Object error) {
  if (error is AppException) return error.message;
  if (error is SocketException || error is TimeoutException || error is HandshakeException) {
    return 'Sem ligação à internet. Verifica a tua rede e tenta novamente.';
  }
  if (error is ApiException) return _apiError(error);
  final text = error.toString();
  if (text.contains('ClientException') || text.contains('SocketException')) {
    return 'Sem ligação à internet. Verifica a tua rede e tenta novamente.';
  }
  return 'Ocorreu um erro inesperado. Tenta novamente.';
}

String _apiError(ApiException e) => switch (e.code) {
  'invalid_credentials' => 'Email, username ou palavra-passe incorretos.',
  'google_account' => 'Esta conta foi criada com o Google. Usa "Continuar com Google".',
  'email_taken' => 'Já existe uma conta com este email.',
  'username_taken' => 'Este username já está a ser usado.',
  'phone_taken' => 'Este telemóvel já está associado a outra conta.',
  'rate_limited' => 'Demasiadas tentativas. Aguarda um pouco e tenta novamente.',
  'session_expired' || 'invalid_refresh_token' || 'unauthorized' => 'A tua sessão expirou. Inicia sessão novamente.',
  'invalid_reset_token' => 'Este link já foi usado ou expirou. Pede um novo email de recuperação.',
  'google_not_configured' => 'O login com Google ainda não está disponível.',
  'invalid_google_token' => 'Não foi possível validar a conta Google. Tenta novamente.',
  'forbidden' => 'Não tens permissão para realizar esta ação.',
  'not_found' => 'Este registo já não existe. Atualiza e tenta novamente.',
  'validation_error' || 'invalid_value' || 'invalid_reference' => 'Há um valor inválido. Confirma os dados.',
  'too_large' || 'unsupported_media_type' => 'Não foi possível carregar a fotografia.',
  _ when e.status >= 500 => 'O servidor está indisponível. Tenta novamente daqui a pouco.',
  _ => 'Não foi possível guardar as alterações. Tenta novamente.',
};
