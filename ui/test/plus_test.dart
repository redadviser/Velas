import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/people/history_screen.dart';
import 'package:aniversarios/services/home_widget_sync.dart';
import 'package:aniversarios/services/reminder_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('pt_PT');
  });

  test('o Birthdayly+ vale enquanto plus_until for futuro', () {
    final p = UserProfile.fromJson({
      'display_name': 'Nuno',
      'plus_until': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
      'plus_trial_available': false,
      'weekly_digest': true,
    }, id: 'u1', email: 'n@ex.pt');
    expect(p.isPlus, isTrue);
    expect(p.plusTrialAvailable, isFalse);
    expect(p.weeklyDigest, isTrue);
    expect(p.toPrefsJson()['weekly_digest'], isTrue);
    expect(p.copyWith(plusUntil: () => DateTime.now().subtract(const Duration(days: 1))).isPlus, isFalse);
    expect(UserProfile.fromJson(const {}, id: 'u2', email: 'x@ex.pt').isPlus, isFalse);
  });

  test('a hora própria do lembrete vai e vem no JSON da pessoa', () {
    final p = Person(id: 'p1', name: 'Pai', day: 9, month: 9, createdAt: DateTime(2026)).copyWith(
      reminderTime: () => (hour: 20, minute: 30),
    );
    expect((p.reminderHour, p.reminderMinute), (20, 30));
    final back = Person.fromJson(p.toJson());
    expect((back.reminderHour, back.reminderMinute), (20, 30));
    expect(p.copyWith(reminderTime: () => null).reminderHour, isNull);
  });

  test('o resumo semanal junta os aniversários da semana, por ordem', () {
    final monday = DateTime(2026, 10, 19);
    final people = [
      Person(id: 'a', name: 'Rui Gomes', day: 24, month: 10, createdAt: DateTime(2026)), // sábado
      Person(id: 'b', name: 'Ana Silva', day: 21, month: 10, createdAt: DateTime(2026)), // quarta
      Person(id: 'c', name: 'Bea', day: 2, month: 11, createdAt: DateTime(2026)), // semana seguinte
    ];
    final d = ReminderCopy.weeklyDigest(people, monday)!;
    expect(d.title, '🎂 Esta semana fazem anos 2 pessoas');
    expect(d.body, 'Ana (quarta), Rui (sábado).');
    expect(ReminderCopy.route(d.payload), '/agenda');
    expect(ReminderCopy.weeklyDigest([people.last], monday), isNull);
  });

  test('o widget mostra os próximos 4 aniversários só com o Birthdayly+', () {
    final people = [
      for (final (i, n) in ['Ana', 'Bea', 'Rui', 'Tó', 'Zé'].indexed)
        Person(id: '$i', name: n, day: 1 + i, month: 12, createdAt: DateTime(2026)),
    ];
    final plus = homeWidgetText(people, plus: true);
    expect(plus.title, 'Próximos aniversários');
    expect(plus.lines.split('\n'), hasLength(4));
    expect(plus.lines, startsWith('Ana · 1 de dezembro'));
    expect(homeWidgetText(people, plus: false).lines, contains('Ativa o Birthdayly+'));
  });

  test('o histórico lê os anos, cartões e prendas do servidor', () {
    final y = HistoryYear.fromJson({
      'year': 2026,
      'cards': [
        {'body': 'Parabéns, pai!', 'via': 'wall', 'created_at': '2026-09-09T10:00:00Z', 'media_kind': 'video'},
      ],
      'gifts': [
        {'title': 'Relógio', 'price': 80, 'purchased_at': '2026-09-01T10:00:00Z'},
      ],
      'group_gifts': [],
    });
    expect(y.year, 2026);
    expect(y.cards.single.onWall, isTrue);
    expect(y.cards.single.mediaKind, 'video');
    expect(y.gifts.single.price, 80);
    expect(y.isEmpty, isFalse);
  });

  test('cada tema muda a cor principal e o gradiente da marca', () {
    for (final a in AppAccent.values) {
      final light = AppTheme.light(accent: a);
      final dark = AppTheme.dark(accent: a);
      expect(light.colorScheme.primary, a.light);
      expect(dark.colorScheme.primary, a.dark);
      expect(light.extension<AppPalette>()!.brand.colors, a.gradient);
    }
    // Sem tema escolhido fica o Coral, o de sempre.
    expect(AppTheme.light().colorScheme.primary, AppColors.primary);
  });
}
