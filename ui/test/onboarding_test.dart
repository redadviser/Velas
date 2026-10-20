import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/people/onboarding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final empty = AppData.empty.copyWith(loaded: true);
  final withPeople = empty.copyWith(
    people: [Person(id: 'p1', name: 'Ana', day: 3, month: 5, createdAt: DateTime(2026))],
  );

  test('abre na primeira entrada numa conta sem aniversários', () {
    expect(onboardingFor(seen: false, data: empty, location: '/home'), Onboarding.open);
  });

  test('espera pelos dados e pelo Início (um link de cartão ou convite tem prioridade)', () {
    expect(onboardingFor(seen: false, data: null, location: '/home'), Onboarding.wait);
    expect(onboardingFor(seen: false, data: AppData.empty, location: '/home'), Onboarding.wait);
    expect(onboardingFor(seen: false, data: empty, location: '/card/AbCdEfGhIjKlMnOpQrStUv'), Onboarding.wait);
    expect(onboardingFor(seen: false, data: empty, location: '/join/K7P2QX9M'), Onboarding.wait);
  });

  test('não volta a abrir, nem abre para quem já tem aniversários', () {
    expect(onboardingFor(seen: true, data: empty, location: '/home'), Onboarding.skip);
    expect(onboardingFor(seen: false, data: withPeople, location: '/home'), Onboarding.skip);
  });
}
