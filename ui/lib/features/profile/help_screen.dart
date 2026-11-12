import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import 'legal.dart';
import '../../core/i18n/translations.dart';

/// Perguntas frequentes (pergunta, resposta).
List<(String, String)> get helpFaq => [
  (
    tr('Como adiciono aniversários?'),
    tr(
      'No separador Pessoas, toca em + para adicionar à mão. Também podes importar dos contactos ou do calendário do '
      'telemóvel (Google Calendar, Outlook), ou enviar um link para os teus amigos deixarem a data deles.',
    ),
  ),
  (
    tr('Não estou a receber os lembretes.'),
    tr(
      'Confirma que as notificações estão ativas em Perfil → Notificações e nas definições do telemóvel. Em alguns '
      'Android, a poupança de bateria trava as notificações: retira a Birthdayly da otimização de bateria. '
      'A hora do aviso muda-se em Perfil → Hora do lembrete.',
    ),
  ),
  (
    tr('Posso deixar a mensagem de parabéns agendada?'),
    tr(
      'Sim. Escreve a mensagem na página da pessoa e toca em Agendar. Se for um amigo na Birthdayly, a mensagem vai '
      'sozinha para o mural dele. Se não, à hora marcada avisamos-te com a mensagem pronta para enviares por '
      'WhatsApp, SMS ou cartão.',
    ),
  ),
  (
    tr('Como funcionam as prendas em grupo?'),
    tr(
      'Quem cria o grupo define a prenda e o valor, e convida os outros. Cada pessoa paga a sua parte diretamente a '
      'quem compra (MB WAY, Revolut, PayPal ou em mão) e marca que já pagou. A Birthdayly não recebe nem guarda '
      'dinheiro.',
    ),
  ),
  (
    tr('Como cancelo o Birthdayly+?'),
    tr(
      'A subscrição é gerida pela loja. No iPhone: Definições → o teu nome → Subscrições. No Android: Google Play → '
      'Perfil → Pagamentos e subscrições → Subscrições. O plano mantém-se até ao fim do período já pago.',
    ),
  ),
  (
    tr('Mudei de telemóvel. Perco os meus dados?'),
    tr(
      'Não. Entra com a mesma conta e está tudo lá. Se tinhas o Birthdayly+, toca em Restaurar compras em '
      'Perfil → Plano.',
    ),
  ),
  (
    tr('Esqueci-me da palavra-passe.'),
    tr('No ecrã de entrada, toca em "Esqueceste-te da palavra-passe?" e enviamos-te um link para criares outra.'),
  ),
  (
    tr('Como apago a minha conta?'),
    tr(
      'Em Perfil → Eliminar conta. Enviamos-te um email com um link e a conta só é apagada quando confirmares. '
      'Se tiveres o Birthdayly+, cancela também a subscrição na loja.',
    ),
  ),
];

/// Livro de Reclamações Eletrónico (obrigatório para serviços a consumidores em Portugal).
const complaintsBookUrl = 'https://www.livroreclamacoes.pt/Inicio/';

/// Ajuda e contacto: perguntas frequentes, reportar um problema, reclamações e o email de apoio.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static String get _device {
    if (kIsWeb) return 'web';
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }

  Future<void> _mail(BuildContext context, String email, String subject, [String body = '']) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      // Uri.queryParameters codifica os espaços como "+", que alguns clientes de email mostram tal e qual.
      query: 'subject=${Uri.encodeComponent(subject)}${body.isEmpty ? '' : '&body=${Uri.encodeComponent(body)}'}',
    );
    final ok = await launchUrl(uri).catchError((_) => false);
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: email));
      if (context.mounted) {
        showMessage(context, context.tr('Não há app de email. Copiámos o endereço: {email}', {'email': email}));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.palette.mutedForeground;
    final email = ref.watch(legalInfoProvider).value?.supportEmail ?? LegalLinks.supportEmail;

    Widget action(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.colors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.text.bodySmall?.copyWith(color: muted)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: muted),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Ajuda e contacto'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(context.tr('Perguntas frequentes'), style: context.text.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, (q, a)) in helpFaq.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  Theme(
                    // Sem as linhas que o ExpansionTile põe ao abrir.
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(q, style: context.text.bodyLarge),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(a, style: context.text.bodyMedium?.copyWith(color: muted))],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(context.tr('Não encontraste resposta?'), style: context.text.titleMedium),
          const SizedBox(height: 8),
          action(
            LucideIcons.bug,
            context.tr('Reportar um problema'),
            context.tr('Algo não funciona como devia. Conta-nos o que aconteceu.'),
            () => _mail(
              context,
              email,
              'Birthdayly: problema',
              'O que aconteceu:\n\n\nO que estavas a fazer:\n\n\n---\nTelemóvel: $_device',
            ),
          ),
          action(
            LucideIcons.messageCircleQuestion,
            context.tr('Outra dúvida ou sugestão'),
            context.tr('Respondemos por email.'),
            () => _mail(context, email, 'Birthdayly: dúvida'),
          ),
          action(
            LucideIcons.messageSquareWarning,
            context.tr('Fazer uma reclamação'),
            context.tr('Escreve-nos, ou usa o Livro de Reclamações Eletrónico.'),
            () => _complaint(context, email),
          ),
          const SizedBox(height: 16),
          Text(context.tr('Contacto'), style: context.text.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Icon(LucideIcons.mail, size: 18, color: muted),
                const SizedBox(width: 12),
                Expanded(child: SelectableText(email, style: context.text.bodyLarge)),
                IconButton(
                  tooltip: context.tr('Copiar'),
                  icon: const Icon(LucideIcons.copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: email));
                    if (context.mounted) showMessage(context, context.tr('Email copiado.'));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _complaint(BuildContext context, String email) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ctx.tr('Fazer uma reclamação'), style: ctx.text.titleLarge),
            const SizedBox(height: 8),
            Text(
              ctx.tr(
                'Lamentamos que algo tenha corrido mal. Escreve-nos e respondemos o mais depressa possível. '
                'Também podes registar a reclamação no Livro de Reclamações Eletrónico.',
              ),
              style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _mail(context, email, 'Birthdayly: reclamação');
              },
              icon: const Icon(LucideIcons.mail, size: 18),
              label: Text(ctx.tr('Escrever-nos')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                openLegal(context, complaintsBookUrl);
              },
              icon: const Icon(LucideIcons.bookOpen, size: 18),
              label: Text(ctx.tr('Livro de Reclamações')),
            ),
          ],
        ),
      ),
    ),
  );
}
