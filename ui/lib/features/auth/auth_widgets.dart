import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// Estrutura comum aos ecrãs de autenticação.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.children, this.footer});

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? IconButton(icon: const Icon(LucideIcons.arrowLeft), onPressed: () => context.pop())
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 36)),
                  const SizedBox(height: 32),
                  Text(title, style: AppTheme.display(context, size: 30)),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground, fontSize: 15),
                  ),
                  const SizedBox(height: 32),
                  ...children,
                  if (footer != null) ...[const SizedBox(height: 24), footer!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.text.labelLarge?.copyWith(fontSize: 14))),
        ?trailing,
      ],
    ),
  );
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.hint = '••••••••',
    this.validator,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final Iterable<String> autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _obscure,
    autofillHints: widget.autofillHints,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onSubmitted,
    validator: widget.validator,
    decoration: InputDecoration(
      hintText: widget.hint,
      prefixIcon: const Icon(LucideIcons.lock, size: 18),
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Mostrar' : 'Ocultar',
        icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  );
}

class LoadingButton extends StatelessWidget {
  const LoadingButton({super.key, required this.label, required this.loading, required this.onPressed, this.icon});

  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: loading ? null : onPressed,
    child: loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: context.colors.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 18)],
            ],
          ),
  );
}

class Validators {
  const Validators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Indica o teu email.';
    if (!_email.hasMatch(v.trim())) return 'Este email não parece válido.';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Indica a palavra-passe.';
    if (v.length < 8) return 'Usa pelo menos 8 caracteres.';
    return null;
  }

  static String? required(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;
}

/// "Continuar com Google", com o separador "ou" opcional. Só aparece quando
/// o servidor e o Google estão configurados.
class GoogleAuthButton extends ConsumerStatefulWidget {
  const GoogleAuthButton({super.key, this.divider = true});

  final bool divider;

  @override
  ConsumerState<GoogleAuthButton> createState() => _GoogleAuthButtonState();
}

class _GoogleAuthButtonState extends ConsumerState<GoogleAuthButton> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    await runGuarded(context, () => ref.read(authRepositoryProvider).signInWithGoogle());
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(authRepositoryProvider).supportsGoogle) return const SizedBox.shrink();
    final muted = context.palette.mutedForeground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.divider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                Expanded(child: Divider(color: context.palette.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou', style: TextStyle(color: muted)),
                ),
                Expanded(child: Divider(color: context.palette.border)),
              ],
            ),
          ),
        OutlinedButton(
          onPressed: _loading ? null : _signIn,
          child: _loading
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [GoogleLogo(), SizedBox(width: 10), Text('Continuar com Google')],
                ),
        ),
      ],
    );
  }
}

/// O "G" do Google, desenhado (sem imagens).
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GoogleLogoPainter());
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (size.width - w) / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    double deg(double d) => d * math.pi / 180;
    void arc(Color color, double from, double to) =>
        canvas.drawArc(rect, deg(from), deg(to - from), false, paint..color = color);
    arc(_blue, 0, 45);
    arc(_green, 45, 135);
    arc(_yellow, 135, 210);
    arc(_red, 210, 315);
    canvas.drawRect(
      Rect.fromLTWH(size.width / 2, (size.height - w) / 2, size.width / 2, w),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
