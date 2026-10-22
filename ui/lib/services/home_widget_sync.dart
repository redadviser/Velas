import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/providers.dart';
import '../core/utils/birthday_utils.dart';
import '../data/models/models.dart';
import '../features/profile/plus.dart';

/// O texto do widget do ecrã inicial: os próximos 4 aniversários (Birthdayly+).
({String title, String lines}) homeWidgetText(List<Person> upcoming, {required bool plus}) {
  if (!plus) {
    return (title: 'Birthdayly+', lines: 'Ativa o Birthdayly+ para veres aqui os próximos aniversários.');
  }
  if (upcoming.isEmpty) {
    return (title: 'Próximos aniversários', lines: 'Ainda não tens aniversários. Abre a app para os acrescentar.');
  }
  final lines = [
    for (final p in upcoming.take(4))
      '${p.isToday ? '🎂 ' : ''}${p.firstName} · ${p.isToday ? 'hoje' : Fmt.dayMonth(p.nextBirthday())}',
  ];
  return (title: 'Próximos aniversários', lines: lines.join('\n'));
}

/// Mantém o widget do Android atualizado com os dados e o plano. No iOS o
/// widget precisa de uma extensão WidgetKit no Xcode (ainda não existe).
final homeWidgetSyncProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  final data = ref.watch(appDataProvider).value;
  if (data == null || !data.loaded) return;
  final text = homeWidgetText(data.upcoming, plus: ref.watch(isPlusProvider));
  Future(() async {
    try {
      await HomeWidget.saveWidgetData<String>('title', text.title);
      await HomeWidget.saveWidgetData<String>('lines', text.lines);
      await HomeWidget.updateWidget(qualifiedAndroidName: 'com.velas.app.BirthdaysWidget');
    } catch (_) {
      // Sem widget no ecrã inicial ou plugin indisponível: nada a fazer.
    }
  });
});
