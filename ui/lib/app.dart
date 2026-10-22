import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/chat_providers.dart';
import 'core/i18n/translations.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/legal.dart';
import 'services/home_widget_sync.dart';

class VelasApp extends ConsumerWidget {
  const VelasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationSyncProvider);
    ref.watch(chatNotificationsProvider);
    ref.watch(pushRegistrationProvider);
    ref.watch(dataSyncProvider);
    ref.watch(homeWidgetSyncProvider);
    final router = ref.watch(routerProvider);
    final accent = ref.watch(effectiveAccentProvider);
    final a11y = ref.watch(accessibilityProvider);

    return MaterialApp.router(
      title: 'Birthdayly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent: accent, highContrast: a11y.highContrast, reduceMotion: a11y.reduceMotion),
      darkTheme: AppTheme.dark(accent: accent, highContrast: a11y.highContrast, reduceMotion: a11y.reduceMotion),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      // Acessibilidade escolhida na app, por cima da do telemóvel, e os termos por aceitar.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: a11y.textScale == null ? media.textScaler : TextScaler.linear(a11y.textScale!),
            disableAnimations: media.disableAnimations || a11y.reduceMotion,
            highContrast: media.highContrast || a11y.highContrast,
          ),
          child: TermsGate(child: child ?? const SizedBox.shrink()),
        );
      },
      // A língua do telemóvel (entre pt, en, es e fr), salvo se for escolhida no perfil.
      locale: ref.watch(localeProvider),
      supportedLocales: Translations.supportedLocales,
      localeListResolutionCallback: (preferred, _) => Translations.resolve(preferred),
      localizationsDelegates: const [Translations.delegate, ...GlobalMaterialLocalizations.delegates],
    );
  }
}
