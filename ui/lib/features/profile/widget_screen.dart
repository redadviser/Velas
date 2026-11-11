import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';

/// O widget do ecrã principal (só Android: BirthdaysWidget.kt).
class WidgetScreen extends ConsumerStatefulWidget {
  const WidgetScreen({super.key});

  @override
  ConsumerState<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends ConsumerState<WidgetScreen> {
  bool _canPin = false;
  bool _waiting = false;

  /// Quantos widgets do Birthdayly já estão no ecrã principal.
  int _installed = 0;

  @override
  void initState() {
    super.initState();
    HomeWidget.isRequestPinWidgetSupported()
        .then((ok) => mounted ? setState(() => _canPin = ok ?? false) : null)
        .catchError((_) => null);
    _count().then((n) => mounted ? setState(() => _installed = n) : null);
  }

  Future<int> _count() async {
    try {
      return (await HomeWidget.getInstalledWidgets()).length;
    } catch (_) {
      return 0;
    }
  }

  /// O Android não diz se o widget foi posto (e alguns launchers, como o da
  /// Xiaomi, põem-no sem perguntar): vê-se pela contagem durante uns segundos.
  Future<void> _pin() async {
    final before = await _count();
    setState(() => _waiting = true);
    await HomeWidget.requestPinWidget(qualifiedAndroidName: 'com.velas.app.BirthdaysWidget');
    var now = before;
    for (var i = 0; i < 40 && now <= before && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      now = await _count();
    }
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _installed = now;
    });
    showMessage(
      context,
      now > before
          ? 'Widget adicionado ao ecrã principal. Para o mudar de sítio, toca sem soltar nele.'
          : 'O widget não foi adicionado.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final next = data.upcoming.take(3).toList();
    final muted = context.palette.mutedForeground;
    return Scaffold(
      appBar: AppBar(title: const Text('Widgets')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: context.palette.softGradient,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: next.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Quando guardares aniversários, aparecem aqui os próximos.',
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(color: muted),
                    ),
                  )
                : _MediumPreview(people: next, data: data),
          ),
          const SizedBox(height: 20),
          if (_installed > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.circleCheck, size: 18, color: context.palette.success),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _installed == 1 ? 'Já está no teu ecrã principal.' : 'Tens $_installed no ecrã principal.',
                    style: context.text.bodyMedium?.copyWith(color: context.palette.success),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _canPin && !_waiting ? _pin : null,
            icon: _waiting
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.layoutGrid, size: 18),
            label: Text(
              _waiting
                  ? 'A adicionar…'
                  : _installed > 0
                  ? 'Adicionar outro'
                  : 'Adicionar ao ecrã principal',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _canPin
                ? 'O telemóvel põe-no num espaço livre. Para o mudar de sítio ou de tamanho, toca sem soltar no widget.'
                : 'Este telemóvel não deixa adicionar widgets a partir da app: procura o Birthdayly na lista de widgets do ecrã principal.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _WidgetFrame extends StatelessWidget {
  const _WidgetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: child,
  );
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(7)),
    child: const Icon(LucideIcons.cakeSlice, size: 13, color: Colors.white),
  );
}

class _MediumPreview extends StatelessWidget {
  const _MediumPreview({required this.people, required this.data});

  final List<Person> people;
  final AppData data;

  @override
  Widget build(BuildContext context) => _WidgetFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _Logo(),
            const SizedBox(width: 8),
            Expanded(child: Text('Próximos aniversários', style: context.text.titleSmall)),
          ],
        ),
        for (final p in people) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(
                  child: PersonAvatar(person: p, color: personColor(p, data), size: 32, celebrate: p.isToday),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.firstName, style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
                    Text(
                      Fmt.dayMonth(p.nextBirthday()),
                      style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                    ),
                  ],
                ),
              ),
              DaysPill(days: p.daysUntil()),
            ],
          ),
        ],
      ],
    ),
  );
}
