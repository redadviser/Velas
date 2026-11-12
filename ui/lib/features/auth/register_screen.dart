import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/utils/identity.dart';
import '../profile/legal.dart';
import 'auth_widgets.dart';
import 'identity_fields.dart';
import '../../core/i18n/translations.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _usernameKey = GlobalKey<UsernameFieldState>();
  late final _termsTap = TapGestureRecognizer()..onTap = () => openTerms(context);
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openPrivacy(context);
  bool _phoneTaken = false;
  bool _accepted = false;
  bool _showConsentError = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _username.dispose();
    _phone.dispose();
    _password.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _phoneTaken = false);
    final valid = _form.currentState!.validate();
    setState(() => _showConsentError = !_accepted);
    if (!valid || !_accepted) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final auth = ref.read(authRepositoryProvider);
    final phone = _phone.text.trim().isEmpty ? '' : Identity.toE164(_phone.text)!;
    SignUpResult? result;
    await runGuarded(context, () async {
      final check = await auth.checkAvailability(username: _username.text, phone: phone);
      if (check.usernameTaken || check.phoneTaken) {
        if (check.usernameTaken) _usernameKey.currentState?.markTaken();
        _phoneTaken = check.phoneTaken;
        _form.currentState!.validate();
        return;
      }
      result = await auth.signUp(
        name: _name.text,
        username: _username.text,
        email: _email.text,
        password: _password.text,
        phone: phone,
      );
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (result == SignUpResult.needsEmailConfirmation) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(LucideIcons.mailCheck, color: ctx.colors.primary, size: 32),
          title: Text(ctx.tr('Confirma o teu email'), style: AppTheme.display(ctx, size: 22)),
          content: Text(
            ctx.tr('Enviámos um link para {email}. Abre-o para ativar a conta e depois inicia sessão.', {
              'email': _email.text.trim(),
            }),
            textAlign: TextAlign.center,
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('Entendido')))],
        ),
      );
      if (mounted) context.pushReplacement('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return AuthScaffold(
      title: context.tr('Cria a tua conta'),
      subtitle: context.tr('Leva menos de um minuto. Depois é só adicionar as pessoas de quem gostas.'),
      // Wrap: com letra grande o botão passa para a linha de baixo.
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.tr('Já tens conta?'), style: TextStyle(color: muted)),
          TextButton(onPressed: () => context.pushReplacement('/login'), child: Text(context.tr('Iniciar sessão'))),
        ],
      ),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel(context.tr('Como te chamas?')),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.required(v, context.tr('Indica o teu nome.')),
                  decoration: InputDecoration(
                    hintText: context.tr('O teu nome'),
                    prefixIcon: const Icon(LucideIcons.user, size: 18),
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel(context.tr('Username')),
                UsernameField(key: _usernameKey, controller: _username, textInputAction: TextInputAction.next),
                const SizedBox(height: 18),
                FieldLabel(context.tr('Email')),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: Validators.email,
                  decoration: const InputDecoration(
                    hintText: 'nome@exemplo.com',
                    prefixIcon: Icon(LucideIcons.mail, size: 18),
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel(
                  context.tr('Telemóvel'),
                  trailing: Text(context.tr('Opcional'), style: context.text.labelSmall?.copyWith(color: muted)),
                ),
                PhoneField(controller: _phone, taken: _phoneTaken, textInputAction: TextInputAction.next),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    context.tr('Permite que os teus amigos te encontrem e convidem pelo número.'),
                    style: context.text.bodySmall?.copyWith(color: muted),
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel(context.tr('Palavra-passe')),
                PasswordField(
                  controller: _password,
                  hint: context.tr('Mínimo 8 caracteres'),
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.password,
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _accepted = !_accepted;
                    if (_accepted) _showConsentError = false;
                  }),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _accepted,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => setState(() {
                          _accepted = v ?? false;
                          if (_accepted) _showConsentError = false;
                        }),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text.rich(
                            TextSpan(
                              style: context.text.bodySmall?.copyWith(color: muted, fontSize: 13),
                              children: [
                                TextSpan(
                                  text: context.tr('Tenho {age} anos ou mais e aceito os ', {'age': kMinimumAge}),
                                ),
                                TextSpan(
                                  text: context.tr('Termos de Utilização'),
                                  style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600),
                                  recognizer: _termsTap,
                                ),
                                TextSpan(text: context.tr(' e a ')),
                                TextSpan(
                                  text: context.tr('Política de Privacidade'),
                                  style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600),
                                  recognizer: _privacyTap,
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showConsentError)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text(
                      context.tr('Precisas de aceitar para continuar.'),
                      style: context.text.bodySmall?.copyWith(color: context.colors.error),
                    ),
                  ),
                const SizedBox(height: 24),
                LoadingButton(label: context.tr('Criar conta'), loading: _loading, onPressed: _submit),
                const GoogleAuthButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
