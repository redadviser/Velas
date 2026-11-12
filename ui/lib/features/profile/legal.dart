import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_widgets.dart';
import '../../core/i18n/translations.dart';

/// Idade mínima para usar a app (igual ao servidor, modules/legal).
const kMinimumAge = 16;

/// Versão dos termos, idade mínima e contacto de apoio (GET /legal/info).
typedef LegalInfo = ({String termsVersion, String? supportEmail, String privacyUrl, String termsUrl});

String get _base => Env.apiUrl.replaceFirst(RegExp(r'/+$'), '');

/// Os links das páginas legais: os Termos são servidos pelo backend; a
/// Política de Privacidade é uma só, a da empresa (RedAdviser), no site dela.
class LegalLinks {
  const LegalLinks._();

  static const privacy = 'https://redadviser.com/?page_id=316';

  /// O email de apoio, enquanto o servidor não responde (GET /legal/info).
  static const supportEmail = 'webmaster@eupasoft.com';
  static String get terms => '$_base/legal/termos';
}

/// `null` sem servidor (modo local).
final legalInfoProvider = FutureProvider<LegalInfo?>((ref) async {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  final j = ((await api.getPublic('/legal/info')) as Map).cast<String, dynamic>();
  return (
    termsVersion: j['terms_version'] as String,
    supportEmail: j['support_email'] as String?,
    privacyUrl: j['privacy_url'] as String? ?? LegalLinks.privacy,
    termsUrl: j['terms_url'] as String? ?? LegalLinks.terms,
  );
});

/// Abre a política ou os termos dentro da app (ou no browser, se não der).
Future<void> openLegal(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  var ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView).catchError((_) => false);
  if (!ok) ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) showMessage(context, context.tr('Não foi possível abrir a página. Tenta mais tarde.'));
}

bool _online(BuildContext context) => ProviderScope.containerOf(context, listen: false).read(apiClientProvider) != null;

/// Os Termos completos; sem servidor (modo local), o resumo.
Future<void> openTerms(BuildContext context) =>
    _online(context) ? openLegal(context, LegalLinks.terms) : showPrivacySheet(context);

/// A Política de Privacidade (no site da empresa).
Future<void> openPrivacy(BuildContext context) => openLegal(context, LegalLinks.privacy);

/// Resumo da privacidade em linguagem simples, com links para os documentos completos.
Future<void> showPrivacySheet(BuildContext context) {
  final online = _online(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text(ctx.tr('Privacidade, em linguagem simples'), style: AppTheme.display(ctx, size: 22)),
          const SizedBox(height: 16),
          for (final (title, body) in [
            (
              ctx.tr('Que dados guardamos'),
              ctx.tr(
                'A tua conta (nome, email, username), os aniversários que acrescentas e o que partilhas na app: conversas, cartões, mural e prendas em grupo.',
              ),
            ),
            (
              ctx.tr('Para que servem'),
              ctx.tr(
                'Para te lembrar de aniversários e para as conversas, os cartões e as prendas em grupo funcionarem. Não vendemos os teus dados nem os usamos para publicidade.',
              ),
            ),
            (
              ctx.tr('Com quem partilhamos'),
              ctx.tr(
                'Só com os serviços de que a app precisa (alojamento, entrar com o Google, notificações, GIFs do GIPHY, email e, se subscreveres o Birthdayly+, a App Store ou o Google Play) e com as pessoas a quem envias mensagens ou cartões.',
              ),
            ),
            (
              ctx.tr('Como os protegemos'),
              ctx.tr(
                'As comunicações são cifradas (HTTPS), as palavras-passe nunca são guardadas em texto simples e cada conta só tem acesso aos seus próprios dados.',
              ),
            ),
            (
              ctx.tr('Os teus direitos'),
              ctx.tr(
                'Podes exportar, corrigir ou eliminar os teus dados a qualquer momento, no Perfil. Também podes reclamar à CNPD.',
              ),
            ),
            (
              ctx.tr('Idade mínima'),
              ctx.tr('A Birthdayly é para pessoas com {age} anos ou mais.', {'age': kMinimumAge}),
            ),
          ]) ...[
            Text(title, style: ctx.text.titleSmall),
            const SizedBox(height: 4),
            Text(body, style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground)),
            const SizedBox(height: 16),
          ],
          OutlinedButton(
            onPressed: () => openLegal(ctx, LegalLinks.privacy),
            child: Text(ctx.tr('Política de Privacidade completa')),
          ),
          if (online) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => openLegal(ctx, LegalLinks.terms),
              child: Text(ctx.tr('Termos de Utilização')),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Exportar os dados (RGPD): com servidor, tudo o que lá está, num ficheiro JSON.
Future<void> exportMyData(BuildContext context, WidgetRef ref) async {
  final api = ref.read(apiClientProvider);
  Uint8List? bytes;
  final ok = await runGuarded(context, () async {
    final data = api != null ? await api.get('/me/export') : ref.read(dataProvider).toExportJson();
    bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
  });
  if (!ok || bytes == null) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes!, name: 'birthdayly-dados.json', mimeType: 'application/json')],
      fileNameOverrides: const ['birthdayly-dados.json'],
      subject: tr('Birthdayly: os meus dados'),
    ),
  );
}

/// Bloqueia a app até a pessoa aceitar a versão atual dos Termos e da
/// Política de Privacidade (contas antigas ou depois de uma atualização).
class TermsGate extends ConsumerStatefulWidget {
  const TermsGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends ConsumerState<TermsGate> {
  bool _accepting = false;
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final info = ref.watch(legalInfoProvider).value;
    final pending = user != null && info != null && user.termsVersion != info.termsVersion;
    if (!pending) return widget.child;
    final firstTime = user.termsVersion == null;
    final muted = context.palette.mutedForeground;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: context.colors.surface,
            child: SafeArea(
              // Desliza quando não cabe (letra grande); senão, o texto fica ao centro e os botões em baixo.
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox.shrink(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(LucideIcons.fileCheck, size: 44, color: context.colors.primary),
                            const SizedBox(height: 16),
                            Text(
                              firstTime
                                  ? context.tr('Antes de continuares')
                                  : context.tr('Atualizámos os nossos termos'),
                              textAlign: TextAlign.center,
                              style: AppTheme.display(context, size: 26),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              context.tr(
                                'Para continuares a usar a Birthdayly, lê e aceita os Termos de Utilização e a Política de Privacidade.',
                              ),
                              textAlign: TextAlign.center,
                              style: context.text.bodyMedium?.copyWith(color: muted),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () => openLegal(context, info.termsUrl),
                              icon: const Icon(LucideIcons.fileText, size: 18),
                              label: Text(context.tr('Termos de Utilização')),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => openLegal(context, info.privacyUrl),
                              icon: const Icon(LucideIcons.shieldCheck, size: 18),
                              label: Text(context.tr('Política de Privacidade')),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              value: _checked,
                              onChanged: (v) => setState(() => _checked = v ?? false),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                context.tr('Tenho {age} anos ou mais e aceito os Termos e a Política de Privacidade.', {
                                  'age': kMinimumAge,
                                }),
                              ),
                            ),
                            const SizedBox(height: 8),
                            LoadingButton(
                              label: context.tr('Aceitar e continuar'),
                              loading: _accepting,
                              onPressed: !_checked
                                  ? null
                                  : () async {
                                      setState(() => _accepting = true);
                                      await runGuarded(context, () => ref.read(authRepositoryProvider).acceptTerms());
                                      if (mounted) setState(() => _accepting = false);
                                    },
                            ),
                            TextButton(
                              onPressed: () => ref.read(authRepositoryProvider).signOut(),
                              child: Text(context.tr('Agora não (terminar sessão)')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
