import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/birthday_utils.dart';

Color swatch(int index) => AppColors.swatches[index % AppColors.swatches.length];

/// Cor de uma pessoa: a da sua categoria ou, sem categoria, uma estável
/// derivada do nome.
Color personColor(Person p, AppData data) {
  final cat = data.category(p.categoryId);
  if (cat != null) return swatch(cat.color);
  return swatch(p.name.codeUnits.fold<int>(0, (a, b) => a + b));
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, required this.color, this.size = 48, this.celebrate = false});

  final Person person;
  final Color color;
  final double size;

  /// Desenha um anel com o gradiente da marca (aniversário hoje).
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = person.photoUrl;
    final ImageProvider? image = url == null
        ? null
        : url.startsWith('http')
        ? NetworkImage(url)
        : FileImage(File(url));

    Widget initials() => Container(
      alignment: Alignment.center,
      color: Color.alphaBlend(color.withValues(alpha: isDark ? 0.28 : 0.16), context.palette.card),
      child: Text(
        person.initials,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          color: isDark ? Color.lerp(color, Colors.white, 0.35) : Color.lerp(color, Colors.black, 0.25),
        ),
      ),
    );

    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: image == null
            ? initials()
            : Image(image: image, fit: BoxFit.cover, errorBuilder: (_, _, _) => initials()),
      ),
    );

    if (!celebrate) return avatar;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: context.palette.card, shape: BoxShape.circle),
        child: avatar,
      ),
    );
  }
}

/// Bloco de calendário (mês + dia) usado nas listas.
class DateTile extends StatelessWidget {
  const DateTile({super.key, required this.date, this.highlight = false, this.width = 50});

  final DateTime date;
  final bool highlight;
  final double width;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? context.colors.onPrimary : context.colors.onSurface;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? context.colors.primary : context.palette.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Fmt.monthShort(date.month),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: highlight ? fg.withValues(alpha: 0.85) : context.colors.primary,
            ),
          ),
          Text('${date.day}', style: AppTheme.display(context, size: 21, color: fg).copyWith(height: 1.1)),
        ],
      ),
    );
  }
}

class DaysPill extends StatelessWidget {
  const DaysPill({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (days) {
      0 => (context.colors.primary, context.colors.onPrimary),
      <= 7 => (context.palette.accent, context.palette.accentForeground),
      _ => (context.palette.muted, context.palette.mutedForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        days == 0 ? 'Hoje 🎉' : Fmt.shortRelative(days),
        style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// Linha de lista com uma pessoa e o seu próximo aniversário.
class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.person,
    required this.data,
    this.onTap,
    this.showDate = true,
    this.trailing,
  });

  final Person person;
  final AppData data;
  final VoidCallback? onTap;
  final bool showDate;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final next = person.nextBirthday();
    final days = person.daysUntil();
    final age = person.turningAge;
    final subtitle = [
      if (age != null) days == 0 ? 'Faz $age hoje' : 'Faz $age',
      if (showDate)
        '${Fmt.weekdayShort(next)}, ${Fmt.dayMonth(next)}'
      else if (person.relation.isNotEmpty)
        person.relation,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            PersonAvatar(person: person, color: personColor(person, data), size: 46, celebrate: days == 0),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.isEmpty ? Fmt.dayMonth(next) : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? DaysPill(days: days),
          ],
        ),
      ),
    );
  }
}
