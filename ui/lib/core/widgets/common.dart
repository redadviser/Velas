import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

/// Superfície base: cartão branco com contorno subtil, sem sombras pesadas.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius);
    return Material(
      color: color ?? context.palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.padding});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 24, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.showName = true, this.onGradient = false});

  final double size;
  final bool showName;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: onGradient ? null : AppColors.brandGradient,
            color: onGradient ? Colors.white.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(size * 0.32),
          ),
          child: Icon(LucideIcons.cake, color: Colors.white, size: size * 0.52),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          Text(
            'Velas',
            style: AppTheme.display(
              context,
              size: size * 0.6,
              color: onGradient ? Colors.white : null,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(gradient: context.palette.softGradient, shape: BoxShape.circle),
            child: Icon(icon, color: context.colors.primary, size: 30),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: AppTheme.display(context, size: 22)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(
      icon: LucideIcons.cloudOff,
      title: 'Algo correu mal',
      message: friendlyError(error),
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(LucideIcons.refreshCw, size: 18),
        label: const Text('Tentar novamente'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(200, 48)),
      ),
    ),
  );
}

/// Pequena etiqueta arredondada.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.background, this.foreground, this.dense = false});

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.palette.mutedForeground;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: background ?? context.palette.muted, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12),
          ),
        ],
      ),
    );
  }
}

/// Executa uma ação, mostrando o erro de forma amigável se falhar.
Future<bool> runGuarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } on SilentException {
    return false;
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Eliminar',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTheme.display(ctx, size: 22)),
      content: Text(message, style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: ctx.colors.onSurface),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(100, 44),
            backgroundColor: destructive ? ctx.colors.error : null,
          ),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}
