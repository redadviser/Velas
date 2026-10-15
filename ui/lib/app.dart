import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/translations.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class VelasApp extends ConsumerWidget {
  const VelasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationSyncProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Birthdayly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      // A língua do telemóvel (entre pt, en, es e fr), salvo se for escolhida no perfil.
      locale: ref.watch(localeProvider),
      supportedLocales: Translations.supportedLocales,
      localeListResolutionCallback: (preferred, _) => Translations.resolve(preferred),
      localizationsDelegates: const [Translations.delegate, ...GlobalMaterialLocalizations.delegates],
    );
  }
}
