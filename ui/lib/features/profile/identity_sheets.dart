import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/identity.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../auth/auth_widgets.dart';
import '../auth/identity_fields.dart';

Future<void> showUsernameSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const _IdentitySheet(editPhone: false),
);

Future<void> showPhoneSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const _IdentitySheet(editPhone: true),
);

class _IdentitySheet extends ConsumerStatefulWidget {
  const _IdentitySheet({required this.editPhone});

  final bool editPhone;

  @override
  ConsumerState<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends ConsumerState<_IdentitySheet> {
  final _form = GlobalKey<FormState>();
  final _usernameKey = GlobalKey<UsernameFieldState>();
  late final UserProfile _user = ref.read(currentUserProvider)!;
  late final _ctrl = TextEditingController(
    text: widget.editPhone ? (_user.phone.isEmpty ? '' : Identity.displayPhone(_user.phone)) : _user.username,
  );
  bool _phoneTaken = false;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    setState(() => _phoneTaken = false);
    if (!remove && !_form.currentState!.validate()) return;
    final auth = ref.read(authRepositoryProvider);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      if (widget.editPhone) {
        final phone = remove ? '' : Identity.toE164(_ctrl.text)!;
        if (phone.isNotEmpty && phone != _user.phone) {
          final check = await auth.checkAvailability(username: '', phone: phone);
          if (check.phoneTaken) {
            setState(() => _phoneTaken = true);
            _form.currentState!.validate();
            throw const SilentException();
          }
        }
        await auth.updateProfile(_user.copyWith(phone: phone));
      } else {
        final username = Identity.normalizeUsername(_ctrl.text);
        if (username != _user.username) {
          final check = await auth.checkAvailability(username: username);
          if (check.usernameTaken) {
            _usernameKey.currentState?.markTaken();
            _form.currentState!.validate();
            throw const SilentException();
          }
        }
        await auth.updateProfile(_user.copyWith(username: username));
      }
    }, success: widget.editPhone ? (remove ? 'Telemóvel removido.' : 'Telemóvel guardado.') : 'Username guardado.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.editPhone ? 'Telemóvel' : 'Username', style: AppTheme.display(context, size: 22)),
              const SizedBox(height: 4),
              Text(
                widget.editPhone
                    ? 'Os teus amigos podem convidar-te para grupos pelo número. Não é mostrado a ninguém.'
                    : 'É assim que os teus amigos te encontram e convidam. Também podes usá-lo para entrar.',
                style: TextStyle(color: context.palette.mutedForeground),
              ),
              const SizedBox(height: 16),
              if (widget.editPhone)
                PhoneField(controller: _ctrl, taken: _phoneTaken, required: true)
              else
                UsernameField(key: _usernameKey, controller: _ctrl, currentUsername: _user.username),
              const SizedBox(height: 20),
              LoadingButton(label: 'Guardar', loading: _saving, onPressed: _save),
              if (widget.editPhone && _user.phone.isNotEmpty)
                TextButton(
                  onPressed: _saving ? null : () => _save(remove: true),
                  style: TextButton.styleFrom(foregroundColor: context.colors.error),
                  child: const Text('Remover telemóvel'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
