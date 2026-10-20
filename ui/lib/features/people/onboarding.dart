import '../../data/models/models.dart';

/// O que fazer ao entrar: na primeira entrada numa conta sem aniversários,
/// abre-se "Adicionar dos contactos" para começar logo.
enum Onboarding {
  /// Ainda não se sabe (dados por carregar, ou noutro ecrã: um link de cartão
  /// ou de convite tem prioridade). Volta-se a ver na próxima mudança.
  wait,

  /// Já foi visto, ou a conta já tem aniversários: não abre e não volta a abrir.
  skip,

  /// Abre o ecrã (e fica marcado como visto).
  open,
}

Onboarding onboardingFor({required bool seen, required AppData? data, required String location}) {
  if (seen) return Onboarding.skip;
  if (data == null || !data.loaded || location != '/home') return Onboarding.wait;
  return data.people.isEmpty ? Onboarding.open : Onboarding.skip;
}

/// Chave (por conta, neste telemóvel) de "já viu o ecrã de boas-vindas".
String onboardingKey(String userId) => 'velas.onboarded.$userId';
