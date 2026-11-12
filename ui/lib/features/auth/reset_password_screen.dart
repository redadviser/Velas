import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import 'auth_widgets.dart';
import '../../core/i18n/translations.dart';

/// Também usado no perfil para alterar a palavra-passe.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).updatePassword(_password.text),
      success: tr('Palavra-passe atualizada.'),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) context.canPop() ? context.pop() : context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: context.tr('Nova palavra-passe'),
      subtitle: context.tr('Escolhe uma palavra-passe com pelo menos 8 caracteres.'),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(context.tr('Nova palavra-passe')),
              PasswordField(
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: Validators.password,
              ),
              const SizedBox(height: 18),
              FieldLabel(context.tr('Confirmar')),
              PasswordField(
                controller: _confirm,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v != _password.text ? context.tr('As palavras-passe não coincidem.') : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 28),
              LoadingButton(label: context.tr('Guardar'), loading: _loading, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}
