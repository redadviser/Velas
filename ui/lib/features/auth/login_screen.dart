import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/identity.dart';
import '../../core/widgets/common.dart';
import 'auth_widgets.dart';

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
      title: 'Bem-vindo de volta',
      subtitle: 'Inicia sessão para veres quem faz anos a seguir.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Ainda não tens conta?', style: TextStyle(color: context.palette.mutedForeground)),
          TextButton(onPressed: () => context.pushReplacement('/register'), child: const Text('Criar conta')),
        ],
      ),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Email ou username'),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Indica o teu email ou username.';
                    if (t.contains('@') && !t.startsWith('@')) return Validators.email(t);
                    return Identity.usernameError(t) == null ? null : 'Username inválido.';
                  },
                  decoration: const InputDecoration(
                    hintText: 'nome@exemplo.com ou @user',
                    prefixIcon: Icon(LucideIcons.atSign, size: 18),
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel(
                  'Palavra-passe',
                  trailing: GestureDetector(
                    onTap: () => context.push('/forgot-password'),
                    child: Text(
                      'Esqueceste-te?',
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                PasswordField(
                  controller: _password,
                  validator: (v) => (v == null || v.isEmpty) ? 'Indica a palavra-passe.' : null,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 28),
                LoadingButton(label: 'Entrar', loading: _loading, onPressed: _submit),
                const GoogleAuthButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
