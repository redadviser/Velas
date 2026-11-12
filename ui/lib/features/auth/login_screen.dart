import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/identity.dart';
import '../../core/widgets/common.dart';
import 'auth_widgets.dart';
import '../../core/i18n/translations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).signIn(identifier: _email.text, password: _password.text),
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: context.tr('Bem-vindo de volta'),
      subtitle: context.tr('Inicia sessão para veres quem faz anos a seguir.'),
      // Wrap: com letra grande o botão passa para a linha de baixo.
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.tr('Ainda não tens conta?'), style: TextStyle(color: context.palette.mutedForeground)),
          TextButton(onPressed: () => context.pushReplacement('/register'), child: Text(context.tr('Criar conta'))),
        ],
      ),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel(context.tr('Email ou username')),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return context.tr('Indica o teu email ou username.');
                    if (t.contains('@') && !t.startsWith('@')) return Validators.email(t);
                    return Identity.usernameError(t) == null ? null : context.tr('Username inválido.');
                  },
                  decoration: InputDecoration(
                    hintText: context.tr('nome@exemplo.com ou @user'),
                    prefixIcon: const Icon(LucideIcons.atSign, size: 18),
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel(context.tr('Palavra-passe')),
                PasswordField(
                  controller: _password,
                  validator: (v) => (v == null || v.isEmpty) ? context.tr('Indica a palavra-passe.') : null,
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    child: Text(context.tr('Esqueceste-te da palavra-passe?')),
                  ),
                ),
                const SizedBox(height: 12),
                LoadingButton(label: context.tr('Entrar'), loading: _loading, onPressed: _submit),
                const GoogleAuthButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
