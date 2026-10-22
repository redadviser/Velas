import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/i18n/translations.dart';
import '../core/providers.dart';
import '../data/models/models.dart';
import '../features/profile/plus.dart';

/// Quantos aniversários vão para o widget (só os primeiros levam fotografia).
const _widgetPeople = 10;
const _widgetPhotos = 3;

/// Os próximos aniversários para o widget, um por linha:
/// "nome|dia|mês|ano|iniciais|fotografia" (vazios quando não há). O widget
/// (BirthdaysWidget.kt) conta quanto falta, por isso não fica desatualizado se
/// a app não for aberta. [photos] = ficheiro local da fotografia, por pessoa.
String homeWidgetPeople(List<Person> upcoming, {Map<String, String> photos = const {}}) {
  String clean(String s) => s.replaceAll(RegExp(r'[|\n]'), ' ');
  return [
    for (final p in upcoming.take(_widgetPeople))
      [clean(p.firstName), p.day, p.month, p.year ?? '', clean(p.initials), photos[p.id] ?? ''].join('|'),
  ].join('\n');
}

/// Copia a fotografia de cada um dos primeiros aniversários para um ficheiro do
/// telemóvel que o widget consegue ler. Só descarrega uma vez por fotografia.
Future<Map<String, String>> _photoFiles(List<Person> upcoming) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/widget');
  await dir.create(recursive: true);
  final out = <String, String>{};
  for (final p in upcoming.take(_widgetPhotos)) {
    final source = p.photoUrl;
    if (source == null) continue;
    // A mesma fotografia tem o mesmo caminho guardado (o URL assinado muda todos os dias).
    final key = (p.photoPath ?? Uri.tryParse(source)?.path ?? source).hashCode.toUnsigned(32);
    final file = File('${dir.path}/${p.id}-$key.img');
    try {
      if (!await file.exists()) {
        if (source.startsWith('http')) {
          final res = await http.get(Uri.parse(source)).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) continue;
          await file.writeAsBytes(res.bodyBytes);
        } else {
          await File(source).copy(file.path);
        }
      }
      out[p.id] = file.path;
    } catch (_) {
      // Sem rede ou sem ficheiro: o widget mostra as iniciais.
    }
  }
  return out;
}

/// Mantém o widget do Android atualizado com os dados, o plano e a língua da
/// app. No iOS o widget precisa de uma extensão WidgetKit no Xcode (ainda não existe).
final homeWidgetSyncProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  final data = ref.watch(appDataProvider).value;
  if (data == null || !data.loaded) return;
  final plus = ref.watch(isPlusProvider);
  final lang = ref.watch(localeProvider)?.languageCode ?? Translations.current.locale.languageCode;
  final upcoming = data.upcoming;
  Future(() async {
    try {
      final photos = plus ? await _photoFiles(upcoming) : const <String, String>{};
      await HomeWidget.saveWidgetData<bool>('plus', plus);
      await HomeWidget.saveWidgetData<String>('lang', lang);
      await HomeWidget.saveWidgetData<String>('people', homeWidgetPeople(upcoming, photos: photos));
      await HomeWidget.updateWidget(qualifiedAndroidName: 'com.velas.app.BirthdaysWidget');
    } catch (_) {
      // Sem widget no ecrã inicial ou plugin indisponível: nada a fazer.
    }
  });
});
