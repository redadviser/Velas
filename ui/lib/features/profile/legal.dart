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

/// Idade mínima para usar a app (igual ao servidor, modules/legal).
const kMinimumAge = 16;

/// Versão dos termos, idade mínima e contacto de apoio (GET /legal/info).
typedef LegalInfo = ({String termsVersion, String? supportEmail, String privacyUrl, String termsUrl});

String get _base => Env.apiUrl.replaceFirst(RegExp(r'/+$'), '');

/// Os links das páginas legais (servidas pelo backend, também para as lojas).
class LegalLinks {
  const LegalLinks._();

  static String get privacy => '$_base/legal/privacidade';
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
  if (!ok && context.mounted) showMessage(context, 'Não foi possível abrir a página. Tenta mais tarde.');
}

bool _online(BuildContext context) => ProviderScope.containerOf(context, listen: false).read(apiClientProvider) != null;

/// Os Termos completos; sem servidor (modo local), o resumo.
Future<void> openTerms(BuildContext context) =>
    _online(context) ? openLegal(context, LegalLinks.terms) : showPrivacySheet(context);

/// A Política de Privacidade completa; sem servidor (modo local), o resumo.
Future<void> openPrivacy(BuildContext context) =>
    _online(context) ? openLegal(context, LegalLinks.privacy) : showPrivacySheet(context);

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
          Text('Privacidade, em linguagem simples', style: AppTheme.display(ctx, size: 22)),
          const SizedBox(height: 16),
          for (final (title, body) in const [
            (
              'Que dados guardamos',
              'A tua conta (nome, email, username), os aniversários que acrescentas e o que partilhas na app: conversas, cartões, mural e prendas em grupo.',
            ),
            (
              'Para que servem',
              'Para te lembrar de aniversários e para as conversas, os cartões e as prendas em grupo funcionarem. Não vendemos os teus dados nem os usamos para publicidade.',
            ),
            (
              'Com quem partilhamos',
              'Só com os serviços de que a app precisa (alojamento, pagamentos com a Stripe, entrar com o Google, GIFs do GIPHY e email) e com as pessoas a quem envias mensagens ou cartões.',
            ),
            (
              'Como os protegemos',
              'As comunicações são cifradas (HTTPS), as palavras-passe nunca são guardadas em texto simples e cada conta só tem acesso aos seus próprios dados.',
            ),
            (
              'Os teus direitos',
              'Podes exportar, corrigir ou eliminar os teus dados a qualquer momento, no Perfil. Também podes reclamar à CNPD.',
            ),
            ('Idade mínima', 'A Birthdayly é para pessoas com $kMinimumAge anos ou mais.'),
          ]) ...[
            Text(title, style: ctx.text.titleSmall),
            const SizedBox(height: 4),
            Text(body, style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground)),
            const SizedBox(height: 16),
          ],
          if (online) ...[
            OutlinedButton(
              onPressed: () => openLegal(ctx, LegalLinks.privacy),
              child: const Text('Política de Privacidade completa'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => openLegal(ctx, LegalLinks.terms),
              child: const Text('Termos de Utilização'),
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
      subject: 'Os meus dados — Birthdayly',
    ),
  );
}

/// Ajuda e contacto: o email de apoio, para copiar ou abrir no email.
Future<void> showHelpSheet(BuildContext context, WidgetRef ref) async {
  final info = await ref.read(legalInfoProvider.future).catchError((_) => null);
  if (!context.mounted) return;
  final email = info?.supportEmail;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ajuda e contacto', style: AppTheme.display(ctx, size: 22)),
            const SizedBox(height: 8),
            Text(
              email == null
                  ? 'Ainda não há um email de apoio configurado. Tenta mais tarde.'
                  : 'Dúvidas, problemas ou pedidos sobre os teus dados: escreve-nos para',
              style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground),
            ),
            if (email != null) ...[
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(child: SelectableText(email, style: ctx.text.bodyLarge)),
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(LucideIcons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: email));
                        if (ctx.mounted) showMessage(ctx, 'Email copiado.');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    launchUrl(Uri(scheme: 'mailto', path: email, query: 'subject=Birthdayly')).catchError((_) => false),
                icon: const Icon(LucideIcons.mail, size: 18),
                label: const Text('Escrever email'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Os direitos do RGPD em linguagem simples, com o que se pode fazer na app.
class PrivacyRightsScreen extends ConsumerWidget {
  const PrivacyRightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.palette.mutedForeground;
    final online = ref.watch(apiClientProvider) != null;
    Widget right(IconData icon, String title, String body, {String? action, VoidCallback? onTap}) => AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: context.text.titleSmall)),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: context.text.bodyMedium?.copyWith(color: muted)),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onTap, child: Text(action)),
            ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Os teus direitos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'O Regulamento Geral sobre a Proteção de Dados (RGPD) dá-te controlo sobre os teus dados. Na Birthdayly podes exercê-lo assim:',
            style: context.text.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          right(
            LucideIcons.download,
            'Acesso e portabilidade',
            'Recebe um ficheiro com tudo o que guardamos sobre ti: perfil, aniversários, ideias, mensagens, cartões, grupos, conversas e pagamentos.',
            action: 'Exportar os meus dados',
            onTap: () => exportMyData(context, ref),
          ),
          const SizedBox(height: 12),
          right(
            LucideIcons.pencil,
            'Retificação',
            'Corrige o teu perfil e os aniversários a qualquer momento, diretamente na app.',
          ),
          const SizedBox(height: 12),
          right(
            LucideIcons.trash2,
            'Apagamento',
            'Eliminar a conta apaga todos os teus dados e ficheiros, exceto os registos de pagamentos que a lei obriga a guardar.',
          ),
          const SizedBox(height: 12),
          right(
            LucideIcons.shieldCheck,
            'Oposição e consentimentos',
            'Desliga as notificações, a presença online e as confirmações de leitura nas definições, e retira o acesso aos contactos, à câmara ou ao microfone nas definições do telemóvel.',
          ),
          const SizedBox(height: 12),
          right(
            LucideIcons.landmark,
            'Reclamação',
            'Se achares que os teus dados não estão a ser bem tratados, podes reclamar à Comissão Nacional de Proteção de Dados (www.cnpd.pt).',
          ),
          if (online) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => openLegal(context, LegalLinks.privacy),
              child: const Text('Ler a Política de Privacidade'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => showHelpSheet(context, ref), child: const Text('Contactar-nos')),
          ],
        ],
      ),
    );
  }
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Icon(LucideIcons.fileCheck, size: 44, color: context.colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      firstTime ? 'Antes de continuares' : 'Atualizámos os nossos termos',
                      textAlign: TextAlign.center,
                      style: AppTheme.display(context, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Para continuares a usar a Birthdayly, lê e aceita os Termos de Utilização e a Política de Privacidade.',
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => openLegal(context, info.termsUrl),
                      icon: const Icon(LucideIcons.fileText, size: 18),
                      label: const Text('Termos de Utilização'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => openLegal(context, info.privacyUrl),
                      icon: const Icon(LucideIcons.shieldCheck, size: 18),
                      label: const Text('Política de Privacidade'),
                    ),
                    const Spacer(),
                    CheckboxListTile(
                      value: _checked,
                      onChanged: (v) => setState(() => _checked = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Tenho $kMinimumAge anos ou mais e aceito os Termos e a Política de Privacidade.'),
                    ),
                    const SizedBox(height: 8),
                    LoadingButton(
                      label: 'Aceitar e continuar',
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
                      child: const Text('Agora não (terminar sessão)'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
