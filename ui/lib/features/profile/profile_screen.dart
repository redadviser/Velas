import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../core/utils/identity.dart';
import '../../services/notification_service.dart';
import '../chat/chat_widgets.dart';
import 'identity_sheets.dart';
import 'legal.dart';
import 'plus.dart';
import '../auth/reset_password_screen.dart';
import '../../core/utils/text.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/cards_providers.dart';
import '../../core/chat_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, UserProfile profile) =>
      runGuarded(context, () => ref.read(authRepositoryProvider).updateProfile(profile));

  Future<void> _editName(BuildContext context, WidgetRef ref, UserProfile user) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _NameSheet(initial: user.name),
    );
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await _update(context, ref, user.copyWith(name: name.trim()));
    }
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, UserProfile user) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: user.reminderHour, minute: user.reminderMinute),
      helpText: 'Hora dos lembretes',
    );
    if (t != null && context.mounted) {
      await _update(context, ref, user.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar conta?',
      message:
          'Todos os aniversários, presentes e mensagens serão apagados de forma permanente. '
          'Esta ação não pode ser desfeita.',
      confirm: 'Eliminar conta',
    );
    if (ok && context.mounted) {
      await runGuarded(context, () => ref.read(authRepositoryProvider).deleteAccount());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final auth = ref.watch(authRepositoryProvider);
    final themeMode = ref.watch(themeModeProvider);
    final data = ref.watch(dataProvider);
    if (user == null) return const Scaffold();

    final time = TimeOfDay(hour: user.reminderHour, minute: user.reminderMinute).format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Row(
            children: [
              _ProfilePhoto(user: user),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: AppTheme.display(context, size: 24)),
                    Text(
                      user.username.isEmpty ? user.email : '@${user.username} · ${user.email}',
                      style: TextStyle(color: context.palette.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(value: '${data.people.length}', label: 'pessoas'),
              const SizedBox(width: 10),
              _MiniStat(value: '${data.gifts.length}', label: 'ideias'),
              const SizedBox(width: 10),
              _MiniStat(value: '${data.messages.length}', label: 'mensagens'),
            ],
          ),
          if (auth.isLocal) ...[
            const SizedBox(height: 16),
            AppCard(
              color: context.palette.accent,
              child: Row(
                children: [
                  Icon(LucideIcons.smartphone, color: context.palette.accentForeground, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Modo local: os dados estão guardados apenas neste dispositivo.',
                      style: TextStyle(color: context.palette.accentForeground),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (ref.watch(cardsRepositoryProvider) != null) ...[
            const SizedBox(height: 16),
            _Section(
              children: [
                _Tile(
                  icon: LucideIcons.partyPopper,
                  title: 'O meu mural',
                  value: '${ref.watch(wallProvider).value?.length ?? 0}',
                  onTap: () => context.push('/wall'),
                ),
                _Tile(
                  icon: LucideIcons.sparkles,
                  title: 'Plano',
                  value: user.isPlus ? 'Birthdayly+' : 'Grátis',
                  onTap: () => context.push('/profile/plans'),
                ),
              ],
            ),
          ],
          const _Group('Conta'),
          _Section(
            children: [
              _Tile(
                icon: LucideIcons.user,
                title: 'Nome',
                value: user.name,
                onTap: () => _editName(context, ref, user),
              ),
              _Tile(
                icon: LucideIcons.atSign,
                title: 'Username',
                value: user.username.isEmpty ? 'Definir' : '@${user.username}',
                onTap: () => showUsernameSheet(context),
              ),
              _Tile(
                icon: LucideIcons.smartphone,
                title: 'Telemóvel',
                value: user.phone.isEmpty ? 'Associar' : Identity.displayPhone(user.phone),
                onTap: () => showPhoneSheet(context),
              ),
              _Tile(
                icon: LucideIcons.wallet,
                title: context.tr(Keys.paymentsScreenTitle),
                value: [
                  if (user.mbwayPayPhone.isNotEmpty || user.payment.mbwayPhone.isNotEmpty) 'MB WAY',
                  if (user.payment.revolutTag.isNotEmpty) 'Revolut',
                  if (user.payment.paypalUser.isNotEmpty) 'PayPal',
                ].join(', ').ifEmpty('Por definir'),
                onTap: () => context.push('/profile/payments'),
              ),
              _Tile(
                icon: LucideIcons.lock,
                title: 'Alterar palavra-passe',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResetPasswordScreen())),
              ),
            ],
          ),
          const _Group('Lembretes'),
          _Section(
            children: [
              SwitchListTile(
                secondary: const Icon(LucideIcons.bell, size: 20),
                title: const Text('Notificações'),
                subtitle: Text(user.notificationsEnabled ? 'Ativas' : 'Desativadas'),
                value: user.notificationsEnabled,
                onChanged: (v) async {
                  if (v) await NotificationService.instance.requestPermission();
                  if (context.mounted) await _update(context, ref, user.copyWith(notificationsEnabled: v));
                },
              ),
              _Tile(
                icon: LucideIcons.clock,
                title: 'Hora do lembrete',
                value: time,
                onTap: () => _pickTime(context, ref, user),
              ),
              SwitchListTile(
                secondary: const Icon(LucideIcons.calendarRange, size: 20),
                title: const Row(children: [Text('Resumo semanal'), SizedBox(width: 8), PlusBadge()]),
                subtitle: const Text('À segunda-feira, os aniversários da semana'),
                value: user.weeklyDigest && user.isPlus,
                onChanged: (v) async {
                  if (v && !await requirePlus(context, ref, feature: 'O resumo semanal')) return;
                  final current = ref.read(currentUserProvider) ?? user;
                  if (context.mounted) await _update(context, ref, current.copyWith(weeklyDigest: v));
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Avisar-me por defeito', style: context.text.titleSmall),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in kReminderOptions)
                          FilterChip(
                            label: Text(reminderLabel(d)),
                            selected: user.defaultReminderDays.contains(d),
                            onSelected: (s) {
                              final set = {...user.defaultReminderDays};
                              s ? set.add(d) : set.remove(d);
                              if (set.isEmpty) {
                                showMessage(context, 'Mantém pelo menos um lembrete.');
                                return;
                              }
                              _update(context, ref, user.copyWith(defaultReminderDays: set.toList()..sort()));
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _Group('Preferências'),
          _Section(
            children: [
              _Tile(
                icon: LucideIcons.accessibility,
                title: 'Acessibilidade',
                value: _a11ySummary(ref.watch(accessibilityProvider)),
                onTap: () => context.push('/profile/accessibility'),
              ),
              _Tile(
                icon: LucideIcons.palette,
                title: 'Tema',
                value: user.isPlus ? ref.watch(themeAccentProvider).label : 'Coral',
                onTap: () => _pickAccent(context, ref),
              ),
              _Tile(
                icon: LucideIcons.tag,
                title: 'Categorias',
                value: '${data.categories.length}',
                onTap: () => context.push('/profile/categories'),
              ),
              if (ref.watch(chatRepositoryProvider) != null)
                _Tile(
                  icon: LucideIcons.messageCircle,
                  title: context.tr(Keys.chatSettingsTitle),
                  onTap: () => context.push('/chat-settings'),
                ),
              _Tile(
                icon: LucideIcons.languages,
                title: context.tr(Keys.settingsLanguage),
                value: switch (ref.watch(localeProvider)) {
                  null => context.tr(Keys.settingsLanguageSystem),
                  final l => context.tr('language.${l.languageCode}'),
                },
                onTap: () => _pickLanguage(context, ref),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aspeto', style: context.text.titleSmall),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(LucideIcons.sun, size: 16),
                            label: Text('Claro'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(LucideIcons.moon, size: 16),
                            label: Text('Escuro'),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _Group('Privacidade e dados'),
          _Section(
            children: [
              _Tile(
                icon: LucideIcons.download,
                title: 'Exportar os meus dados',
                onTap: () => exportMyData(context, ref),
              ),
              _Tile(
                icon: LucideIcons.scale,
                title: 'Os teus direitos (RGPD)',
                onTap: () => context.push('/profile/privacy'),
              ),
              if (ref.watch(apiClientProvider) != null) ...[
                _Tile(
                  icon: LucideIcons.shieldCheck,
                  title: 'Política de Privacidade',
                  onTap: () => openLegal(context, LegalLinks.privacy),
                ),
                _Tile(
                  icon: LucideIcons.fileText,
                  title: 'Termos de Utilização',
                  onTap: () => openLegal(context, LegalLinks.terms),
                ),
              ],
              _Tile(
                icon: LucideIcons.trash2,
                title: 'Eliminar conta',
                destructive: true,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
          const _Group('Ajuda'),
          _Section(
            children: [
              _Tile(icon: LucideIcons.lifeBuoy, title: 'Ajuda e contacto', onTap: () => showHelpSheet(context, ref)),
              if (ref.watch(chatRepositoryProvider) != null)
                _Tile(
                  icon: LucideIcons.ban,
                  title: 'Utilizadores bloqueados',
                  onTap: () => context.push('/chat-settings/blocked'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => runGuarded(context, () => ref.read(authRepositoryProvider).signOut()),
            icon: const Icon(LucideIcons.logOut, size: 18),
            label: const Text('Terminar sessão'),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Birthdayly · versão 1.0.0',
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Column(
        children: [
          Text(value, style: AppTheme.display(context, size: 22)),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
          ),
        ],
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
    child: Text(
      title.toUpperCase(),
      style: context.text.labelSmall?.copyWith(
        color: context.palette.mutedForeground,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), children[i]],
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.value, this.onTap, this.destructive = false});

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.colors.error : null;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                value!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.palette.mutedForeground),
              ),
            ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// Fotografia de perfil: tocar para escolher outra, tirar uma ou remover.
class _ProfilePhoto extends ConsumerStatefulWidget {
  const _ProfilePhoto({required this.user});

  final UserProfile user;

  @override
  ConsumerState<_ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends ConsumerState<_ProfilePhoto> {
  bool _busy = false;

  Future<void> _change() async {
    final hasPhoto = widget.user.photoUrl != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.images),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Tirar fotografia'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(LucideIcons.trash2, color: ctx.colors.error),
                title: Text('Remover fotografia', style: TextStyle(color: ctx.colors.error)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final auth = ref.read(authRepositoryProvider);
    if (action == 'remove') {
      setState(() => _busy = true);
      await runGuarded(context, () => auth.updatePhoto(null), success: 'Fotografia removida.');
    } else {
      PickedImage? picked;
      try {
        // Pequena e quadrada o suficiente para os avatares (até 2 MB no servidor).
        picked = await pickChatImage(action == 'camera' ? ImageSource.camera : ImageSource.gallery, maxSide: 640);
      } catch (_) {
        if (mounted) showMessage(context, 'Não foi possível aceder às fotografias. Verifica as permissões.');
        return;
      }
      if (picked == null || !mounted) return;
      setState(() => _busy = true);
      final bytes = picked.bytes;
      await runGuarded(context, () => auth.updatePhoto(bytes), success: 'Fotografia atualizada.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    const size = 64.0;
    return Semantics(
      button: true,
      label: 'Alterar fotografia de perfil',
      child: GestureDetector(
        onTap: _busy ? null : _change,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: size,
                child: user.photoUrl != null
                    ? ChatImage(url: user.photoUrl)
                    : ColoredBox(
                        color: context.palette.accent,
                        child: Center(
                          child: Text(
                            initialOf(user.name),
                            style: AppTheme.display(context, size: 26, color: context.palette.accentForeground),
                          ),
                        ),
                      ),
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: ClipOval(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.surface, width: 2),
                ),
                child: Icon(LucideIcons.camera, size: 13, color: context.colors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Idioma da app: o do telemóvel ou um escolhido.
/// "130%, contraste" ou "Do telemóvel".
String _a11ySummary(AccessibilitySettings a) {
  final parts = [
    if (a.textScale != null) '${(a.textScale! * 100).round()}%',
    if (a.highContrast) 'contraste',
    if (a.reduceMotion) 'sem animações',
  ];
  return parts.isEmpty ? 'Do telemóvel' : parts.join(', ');
}

/// Tema de cor da app (Birthdayly+).
Future<void> _pickAccent(BuildContext context, WidgetRef ref) async {
  if (!await requirePlus(context, ref, feature: 'Mudar o tema')) return;
  if (!context.mounted) return;
  final current = ref.read(themeAccentProvider);
  final picked = await showModalBottomSheet<AppAccent>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Tema', style: AppTheme.display(ctx, size: 22)),
          ),
          for (final a in AppAccent.values)
            ListTile(
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(gradient: a.brand, shape: BoxShape.circle),
              ),
              title: Text(a.label),
              trailing: a == current ? Icon(LucideIcons.check, color: ctx.colors.primary) : null,
              onTap: () => Navigator.pop(ctx, a),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked != null) ref.read(themeAccentProvider.notifier).set(picked);
}

Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
  final current = ref.read(localeProvider);
  final picked = await showModalBottomSheet<(Locale?,)>(
    context: context,
    builder: (ctx) => SafeArea(
      child: RadioGroup<String>(
        groupValue: current?.languageCode ?? '',
        onChanged: (code) => Navigator.pop(ctx, (
          code == null || code.isEmpty ? null : Translations.supportedLocales.firstWhere((l) => l.languageCode == code),
        )),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(ctx.tr(Keys.settingsLanguage), style: AppTheme.display(ctx, size: 22)),
            ),
            RadioListTile<String>(value: '', title: Text(ctx.tr(Keys.settingsLanguageSystem))),
            for (final code in Translations.languageCodes)
              RadioListTile<String>(value: code, title: Text(ctx.tr('language.$code'))),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (picked != null) ref.read(localeProvider.notifier).set(picked.$1);
}

/// Folha para mudar o nome. A caixa de texto é da folha e só é apagada quando
/// ela sai do ecrã (apagá-la logo ao fechar rebentava durante a animação).
class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initial});

  final String initial;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('O teu nome', style: AppTheme.display(context, size: 22)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
  }
}
