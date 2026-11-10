import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Chuva curta de confettis por cima do ecrã (ex.: pagamento registado).
/// Não faz nada com "reduzir animações" ligado.
void showConfetti(BuildContext context) {
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Confetti(onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..forward().whenComplete(widget.onDone);
  final _pieces = List.generate(48, (_) => _Piece(Random()));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(size: Size.infinite, painter: _Painter(_pieces, _c.value)),
      ),
    ),
  );
}

class _Piece {
  _Piece(Random r)
    : x = r.nextDouble(),
      delay = r.nextDouble() * 0.25,
      speed = 0.8 + r.nextDouble() * 0.6,
      drift = (r.nextDouble() - 0.5) * 0.25,
      spin = (r.nextDouble() - 0.5) * 12,
      color = AppColors.swatches[r.nextInt(AppColors.swatches.length)],
      round = r.nextBool();

  final double x, delay, speed, drift, spin;
  final Color color;
  final bool round;
}

class _Painter extends CustomPainter {
  _Painter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final y = -20 + local * p.speed * size.height;
      final x = (p.x + p.drift * local) * size.width;
      final paint = Paint()..color = p.color.withValues(alpha: 1 - local * local);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p.spin * local);
      if (p.round) {
        canvas.drawCircle(Offset.zero, 4, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -3, 10, 6), const Radius.circular(2)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.t != t;
}
