import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/identity.dart';

enum _Check { idle, checking, available, taken, failed }

/// Campo de username que verifica, enquanto se escreve, se está livre.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({super.key, required this.controller, this.currentUsername = '', this.textInputAction});

  final TextEditingController controller;

  /// O username atual da conta (não conta como ocupado).
  final String currentUsername;
  final TextInputAction? textInputAction;

  @override
  ConsumerState<UsernameField> createState() => UsernameFieldState();
}

class UsernameFieldState extends ConsumerState<UsernameField> {
  Timer? _debounce;
  _Check _check = _Check.idle;
  String _checked = '';

  /// Marca o username como ocupado (ex.: resposta do servidor ao submeter).
  void markTaken() => setState(() {
    _check = _Check.taken;
    _checked = Identity.normalizeUsername(widget.controller.text);
  });

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final u = Identity.normalizeUsername(v);
    if (Identity.usernameError(u) != null || u == widget.currentUsername) {
      setState(() => _check = _Check.idle);
      return;
    }
    setState(() => _check = _Check.checking);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final r = await ref.read(authRepositoryProvider).checkAvailability(username: u);
        if (!mounted || Identity.normalizeUsername(widget.controller.text) != u) return;
        setState(() {
          _checked = u;
          _check = r.usernameTaken ? _Check.taken : _Check.available;
        });
      } catch (_) {
        if (mounted) setState(() => _check = _Check.failed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget? suffix = switch (_check) {
      _Check.checking => const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      _Check.available => Icon(LucideIcons.circleCheck, size: 18, color: context.palette.success),
      _Check.taken => Icon(LucideIcons.circleX, size: 18, color: context.colors.error),
      _ => null,
    };
    return TextFormField(
      controller: widget.controller,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.newUsername],
      textInputAction: widget.textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
        LengthLimitingTextInputFormatter(20),
        TextInputFormatter.withFunction((_, n) => n.copyWith(text: n.text.toLowerCase())),
      ],
      onChanged: _onChanged,
      validator: (v) {
        final error = Identity.usernameError(v ?? '');
        if (error != null) return error;
        if (_check == _Check.taken && _checked == Identity.normalizeUsername(v!)) {
          return 'Este username já está a ser usado.';
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: 'o_teu_username',
        prefixIcon: const Icon(LucideIcons.atSign, size: 18),
        suffixIcon: suffix,
        helperText: _check == _Check.available ? 'Disponível' : null,
        helperStyle: TextStyle(color: context.palette.success, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Telemóvel opcional, guardado em formato internacional.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.taken = false,
    this.textInputAction,
    this.required = false,
  });

  final TextEditingController controller;
  final bool taken;
  final bool required;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      textInputAction: textInputAction,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return required ? 'Indica o número.' : null;
        if (Identity.toE164(t) == null) return 'Número inválido. Ex.: 912 345 678';
        if (taken) return 'Este telemóvel já está associado a outra conta.';
        return null;
      },
      decoration: const InputDecoration(hintText: '912 345 678', prefixIcon: Icon(LucideIcons.smartphone, size: 18)),
    );
  }
}
