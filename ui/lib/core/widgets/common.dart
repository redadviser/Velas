import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../constants.dart';
import '../i18n/translations.dart';

/// Superfície base: cartão com contorno subtil e, se [raised], sombra suave.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.raised = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: raised ? context.palette.shadow : null),
      child: Material(
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
      ),
    );
  }
}

/// Quadrado arredondado com um ícone, usado à esquerda de cartões e opções.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.size = 42, this.background, this.foreground});

  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background ?? context.palette.accent,
      borderRadius: BorderRadius.circular(size * 0.31),
    ),
    child: Icon(icon, size: size * 0.5, color: foreground ?? context.palette.accentForeground),
  );
}

/// Barra de progresso fina com o gradiente coral.
class SoftProgress extends StatelessWidget {
  const SoftProgress({super.key, required this.value, this.height = 7, this.semanticsLabel});

  final double value;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: context.palette.muted)),
              FractionallySizedBox(
                widthFactor: v,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height),
                    gradient: LinearGradient(colors: [context.colors.primary, const Color(0xFFFF8B76)]),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
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
          Expanded(flex: 3, child: Text(title, style: AppTheme.display(context, size: 19))),
          if (action != null)
            Flexible(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(action!, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
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
        Transform.rotate(
          angle: -0.07,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: onGradient ? Colors.white.withValues(alpha: 0.18) : context.colors.primary,
              borderRadius: BorderRadius.circular(size * 0.35),
            ),
            child: Icon(LucideIcons.cake, color: Colors.white, size: size * 0.52),
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Birthdayly',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.display(context, size: size * 0.6, color: onGradient ? Colors.white : null),
            ),
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
    // Com altura limitada e letra grande, rola em vez de transbordar. Sem
    // LayoutBuilder: o SliverFillRemaining pede a altura intrínseca, que ele não dá.
    return SingleChildScrollView(child: _body(context));
  }

  Widget _body(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -0.07,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: context.palette.softGradient,
                borderRadius: BorderRadius.circular(26),
                boxShadow: context.palette.shadow,
              ),
              child: Icon(icon, color: context.colors.primary, size: 32),
            ),
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
      title: context.tr('Algo correu mal'),
      message: friendlyError(error),
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(LucideIcons.refreshCw, size: 18),
        label: Text(context.tr('Tentar novamente')),
        style: OutlinedButton.styleFrom(minimumSize: const Size(200, 48)),
      ),
    ),
  );
}

/// Pequena etiqueta arredondada.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.background,
    this.foreground,
    this.dense = false,
  });

  final String label;
  final IconData? icon;

  /// Em vez de [icon] (ex.: um logótipo).
  final Widget? leading;
  final Color? background;
  final Color? foreground;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.palette.mutedForeground;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: background ?? context.palette.muted, borderRadius: BorderRadius.circular(999)),
      // Um só Text (o ícone vai dentro): com pouco espaço corta com reticências
      // em vez de transbordar, e continua a funcionar dentro de uma Row.
      child: Text.rich(
        TextSpan(
          children: [
            if (leading != null || icon != null) ...[
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: leading ?? Icon(icon, size: dense ? 12 : 14, color: fg),
              ),
              WidgetSpan(child: SizedBox(width: leading != null ? 5 : 4)),
            ],
            TextSpan(text: label),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12),
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTheme.display(ctx, size: 22)),
      content: Text(message, style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: ctx.colors.onSurface),
          child: Text(ctx.tr(Keys.commonCancel)),
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
  return confirmed ?? false;
}

/// Botão de contorno tracejado para "acrescentar mais um" no fim de listas.
class DashedButton extends StatelessWidget {
  const DashedButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.palette.accentForeground;
    return CustomPaint(
      painter: _DashedBorder(context.palette.mutedForeground.withValues(alpha: 0.45), AppTheme.radiusSmall + 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 1),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: context.text.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
