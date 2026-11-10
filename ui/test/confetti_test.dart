import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aniversarios/core/widgets/confetti.dart';

void main() {
  Future<BuildContext> pump(WidgetTester tester, {required bool reduceMotion}) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('aparece e desaparece sozinho', (tester) async {
    final ctx = await pump(tester, reduceMotion: false);
    showConfetti(ctx);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(IgnorePointer), findsWidgets);
    final during = tester.widgetList(find.byType(CustomPaint)).length;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widgetList(find.byType(CustomPaint)).length, lessThan(during));
  });

  testWidgets('com "reduzir animações" não mostra nada', (tester) async {
    final ctx = await pump(tester, reduceMotion: true);
    final before = tester.widgetList(find.byType(CustomPaint)).length;
    showConfetti(ctx);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widgetList(find.byType(CustomPaint)).length, before);
  });
}
