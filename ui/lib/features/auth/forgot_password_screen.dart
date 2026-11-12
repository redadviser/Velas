import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import 'auth_widgets.dart';
import '../../core/i18n/translations.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await runGuarded(context, () => ref.read(authRepositoryProvider).sendPasswordReset(_email.text));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sent = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthScaffold(
        title: context.tr('Verifica o teu email'),
        subtitle: context.tr(
          'Se existir uma conta associada a {email}, vais receber um link para '
          'definir uma nova palavra-passe. Abre-o neste telemóvel.',
          {'email': _email.text.trim()},
        ),
        children: [
          AppCard(
            color: context.palette.accent,
            child: Row(
              children: [
                Icon(LucideIcons.mailCheck, color: context.palette.accentForeground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr(
                      'Não encontras o email? Vê a pasta de spam ou tenta novamente dentro de alguns minutos.',
                    ),
                    style: TextStyle(color: context.palette.accentForeground),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: () => context.pop(), child: Text(context.tr('Voltar ao início de sessão'))),
        ],
      );
    }

    return AuthScaffold(
      title: context.tr('Recuperar palavra-passe'),
      subtitle: context.tr('Indica o email da tua conta e enviamos-te um link para criares uma nova.'),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(context.tr('Email')),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'nome@exemplo.com',
                  prefixIcon: Icon(LucideIcons.mail, size: 18),
                ),
              ),
              const SizedBox(height: 28),
              LoadingButton(
                label: context.tr('Enviar link'),
                loading: _loading,
                onPressed: _submit,
                icon: LucideIcons.send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
