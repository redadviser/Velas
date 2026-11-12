import 'package:flutter/foundation.dart';
import 'package:country_flags/country_flags.dart';
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
      helpText: context.tr('Hora dos lembretes'),
    );
    if (t != null && context.mounted) {
      await _update(context, ref, user.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final online = ref.read(apiClientProvider) != null;
    final ok = await confirmDialog(
      context,
      title: context.tr('Eliminar conta?'),
      message: online
          ? context.tr(
              'Vamos enviar-te um email com um link. A conta e todos os aniversários, presentes e mensagens só são '
              'apagados quando abrires o link e confirmares. Depois disso não é possível recuperar.',
            )
          : context.tr(
              'Todos os aniversários, presentes e mensagens serão apagados de forma permanente. '
              'Esta ação não pode ser desfeita.',
            ),
      confirm: online ? context.tr('Enviar email') : context.tr('Eliminar conta'),
    );
    if (!ok || !context.mounted) return;
    String? email;
    final sent = await runGuarded(context, () async {
      email = await ref.read(authRepositoryProvider).requestAccountDeletion();
    });
    if (!sent || email == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Vê o teu email'), style: AppTheme.display(ctx, size: 22)),
        content: Text(
          ctx.tr(
            'Enviámos um email para {email}. Abre o link e confirma para eliminar a conta. '
            'O link vale 24 horas; se não o encontrares, vê o spam.',
            {'email': email},
          ),
          style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('OK')))],
      ),
    );
  }

  List<Widget> _accountTiles(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    return [
      _Tile(
        icon: LucideIcons.user,
        title: context.tr('Nome'),
        value: user.name,
        onTap: () => _editName(context, ref, user),
      ),
      _Tile(
        icon: LucideIcons.atSign,
        title: context.tr('Username'),
        value: user.username.isEmpty ? context.tr('Definir') : '@${user.username}',
        onTap: () => showUsernameSheet(context),
      ),
      _Tile(
        icon: LucideIcons.smartphone,
        title: context.tr('Telemóvel'),
        value: user.phone.isEmpty ? context.tr('Associar') : Identity.displayPhone(user.phone),
        onTap: () => showPhoneSheet(context),
      ),
      _Tile(
        icon: LucideIcons.wallet,
        title: context.tr(Keys.paymentsScreenTitle),
        value: [
          if (user.payment.mbwayPhone.isNotEmpty) 'MB WAY',
          if (user.payment.revolutTag.isNotEmpty) 'Revolut',
          if (user.payment.paypalUser.isNotEmpty) 'PayPal',
        ].join(', ').ifEmpty(context.tr('Por definir')),
        onTap: () => context.push('/profile/payments'),
      ),
      _Tile(
        icon: LucideIcons.lock,
        title: context.tr('Alterar palavra-passe'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResetPasswordScreen())),
      ),
    ];
  }

  List<Widget> _remindersTiles(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    final time = TimeOfDay(hour: user.reminderHour, minute: user.reminderMinute).format(context);
    return [
      SwitchListTile(
        secondary: const IconBadge(icon: LucideIcons.bell, size: 38),
        title: Text(context.tr('Notificações')),
        subtitle: Text(user.notificationsEnabled ? context.tr('Ativas') : context.tr('Desativadas')),
        value: user.notificationsEnabled,
        onChanged: (v) async {
          if (v) await NotificationService.instance.requestPermission();
          if (context.mounted) await _update(context, ref, user.copyWith(notificationsEnabled: v));
        },
      ),
      _Tile(
        icon: LucideIcons.clock,
        title: context.tr('Hora do lembrete'),
        value: time,
        onTap: () => _pickTime(context, ref, user),
      ),
      SwitchListTile(
        secondary: const IconBadge(icon: LucideIcons.calendarRange, size: 38),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [Text(context.tr('Resumo semanal')), const PlusBadge()],
        ),
        subtitle: Text(context.tr('À segunda-feira, os aniversários da semana')),
        value: user.weeklyDigest && user.isPlus,
        onChanged: (v) async {
          if (v && !await requirePlus(context, ref, feature: context.tr('O resumo semanal'))) return;
          final current = ref.read(currentUserProvider) ?? user;
          if (context.mounted) await _update(context, ref, current.copyWith(weeklyDigest: v));
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Avisar-me por defeito'), style: context.text.titleSmall),
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
                        showMessage(context, context.tr('Mantém pelo menos um lembrete.'));
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
    ];
  }

  List<Widget> _preferencesTiles(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    final themeMode = ref.watch(themeModeProvider);
    final data = ref.watch(dataProvider);
    return [
      _Tile(
        icon: LucideIcons.accessibility,
        title: context.tr('Acessibilidade'),
        value: _a11ySummary(ref.watch(accessibilityProvider)),
        onTap: () => context.push('/profile/accessibility'),
      ),
      _Tile(
        icon: LucideIcons.palette,
        title: context.tr('Tema'),
        value: user.isPlus ? ref.watch(themeAccentProvider).label : context.tr('Coral'),
        onTap: () => _pickAccent(context, ref),
      ),
      _Tile(
        icon: LucideIcons.tag,
        title: context.tr('Categorias'),
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
          final l => Translations.languageNames[Translations.tagOf(l)]!,
        },
        onTap: () => _pickLanguage(context, ref),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Aspeto'), style: context.text.titleSmall),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(context.tr('Sistema'))),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(LucideIcons.sun, size: 16),
                    label: Text(context.tr('Claro')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(LucideIcons.moon, size: 16),
                    label: Text(context.tr('Escuro')),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _privacyTiles(BuildContext context, WidgetRef ref) {
    return [
      _Tile(
        icon: LucideIcons.download,
        title: context.tr('Exportar os meus dados'),
        onTap: () => exportMyData(context, ref),
      ),
      _Tile(
        icon: LucideIcons.shieldCheck,
        title: context.tr('Política de Privacidade'),
        onTap: () => openLegal(context, LegalLinks.privacy),
      ),
      if (ref.watch(apiClientProvider) != null)
        _Tile(
          icon: LucideIcons.fileText,
          title: context.tr('Termos de Utilização'),
          onTap: () => openLegal(context, LegalLinks.terms),
        ),
      _Tile(
        icon: LucideIcons.trash2,
        title: context.tr('Eliminar conta'),
        destructive: true,
        onTap: () => _deleteAccount(context, ref),
      ),
    ];
  }

  List<Widget> _supportTiles(BuildContext context, WidgetRef ref) {
    return [
      _Tile(
        icon: LucideIcons.lifeBuoy,
        title: context.tr('Ajuda e contacto'),
        onTap: () => context.push('/profile/help'),
      ),
      if (ref.watch(chatRepositoryProvider) != null)
        _Tile(
          icon: LucideIcons.ban,
          title: context.tr('Utilizadores bloqueados'),
          onTap: () => context.push('/chat-settings/blocked'),
        ),
    ];
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
      appBar: AppBar(title: Text(context.tr('Perfil'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
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
              _MiniStat(
                value: '${data.people.length}',
                label: context.tr('pessoas'),
                onTap: () => context.go('/people'),
              ),
              const SizedBox(width: 10),
              _MiniStat(
                value: '${data.gifts.length}',
                label: context.tr('ideias'),
                onTap: () => context.go('/gifts?tab=ideas'),
              ),
              const SizedBox(width: 10),
              _MiniStat(
                value: '${data.messages.length}',
                label: context.tr('mensagens'),
                onTap: () => _showMessages(context, data),
              ),
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
                      context.tr('Modo local: os dados estão guardados apenas neste dispositivo.'),
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
                  title: context.tr('O meu mural'),
                  value: '${ref.watch(wallProvider).value?.length ?? 0}',
                  onTap: () => context.push('/wall'),
                ),
                _Tile(
                  icon: LucideIcons.sparkles,
                  title: context.tr('Plano'),
                  value: user.isPlus ? 'Birthdayly+' : context.tr('Grátis'),
                  onTap: () => context.push('/profile/plans'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _Section(
            children: [
              _Tile(
                icon: LucideIcons.circleUserRound,
                title: context.tr('Conta'),
                value: user.username.isEmpty ? user.name : '@${user.username}',
                onTap: () => context.push('/profile/account'),
              ),
              _Tile(
                icon: LucideIcons.bell,
                title: context.tr('Lembretes'),
                value: user.notificationsEnabled
                    ? context.tr('Ativos · {time}', {'time': time})
                    : context.tr('Desligados'),
                onTap: () => context.push('/profile/reminders'),
              ),
              _Tile(
                icon: LucideIcons.lifeBuoy,
                title: context.tr('Ajuda'),
                onTap: () => context.push('/profile/support'),
              ),
              _Tile(
                icon: LucideIcons.slidersHorizontal,
                title: context.tr('Preferências'),
                value: switch (themeMode) {
                  ThemeMode.light => context.tr('Claro'),
                  ThemeMode.dark => context.tr('Escuro'),
                  ThemeMode.system => context.tr('Tema do sistema'),
                },
                onTap: () => context.push('/profile/preferences'),
              ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                _Tile(
                  icon: LucideIcons.layoutGrid,
                  title: context.tr('Widgets'),
                  onTap: () => context.push('/profile/widget'),
                ),
              _Tile(
                icon: LucideIcons.shieldCheck,
                title: context.tr('Privacidade e dados'),
                onTap: () => context.push('/profile/privacy'),
              ),
              _Tile(
                icon: LucideIcons.heart,
                title: context.tr('Gostos e desejos'),
                value: user.interests.isEmpty ? null : context.tr('{count} gostos', {'count': user.interests.length}),
                onTap: () => context.push('/profile/wishlist'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => runGuarded(context, () => ref.read(authRepositoryProvider).signOut()),
            icon: const Icon(LucideIcons.logOut, size: 18),
            label: Text(context.tr('Terminar sessão')),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              context.tr('Birthdayly · versão 1.0.0'),
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

/// As secções do perfil, cada uma na sua página.
enum ProfileSection {
  account,
  reminders,
  preferences,
  privacy,
  support;

  String get title => switch (this) {
    account => tr('Conta'),
    reminders => tr('Lembretes'),
    preferences => tr('Preferências'),
    privacy => tr('Privacidade e dados'),
    support => tr('Ajuda'),
  };
}

class ProfileSectionScreen extends ConsumerWidget {
  const ProfileSectionScreen({super.key, required this.section});

  final ProfileSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserProvider) == null) return const Scaffold();
    const profile = ProfileScreen();
    final tiles = switch (section) {
      ProfileSection.account => profile._accountTiles(context, ref),
      ProfileSection.reminders => profile._remindersTiles(context, ref),
      ProfileSection.preferences => profile._preferencesTiles(context, ref),
      ProfileSection.privacy => profile._privacyTiles(context, ref),
      ProfileSection.support => profile._supportTiles(context, ref),
    };
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [_Section(children: tiles)],
      ),
    );
  }
}

/// As mensagens de parabéns guardadas; cada uma abre o editor dessa pessoa.
void _showMessages(BuildContext context, AppData data) {
  final withMessage = [
    for (final p in data.upcoming)
      if (data.messageFor(p.id) case final m?) (p, m),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(ctx.tr('Mensagens guardadas'), style: AppTheme.display(ctx, size: 22)),
            ),
            if (withMessage.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  ctx.tr('Ainda não escreveste nenhuma. Abre uma pessoa e toca em "Ver mensagem".'),
                  style: TextStyle(color: ctx.palette.mutedForeground),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (p, m) in withMessage)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(LucideIcons.chevronRight, size: 18),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/person/${p.id}/message');
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: AppCard(
      onTap: onTap,
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
      leading: IconBadge(
        icon: icon,
        size: 38,
        background: destructive ? context.colors.error.withValues(alpha: 0.1) : null,
        foreground: color,
      ),
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
        child: SingleChildScrollView(
          // Desliza quando não cabe (letra grande).
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.images),
                title: Text(ctx.tr('Escolher da galeria')),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.camera),
                title: Text(ctx.tr('Tirar fotografia')),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              if (hasPhoto)
                ListTile(
                  leading: Icon(LucideIcons.trash2, color: ctx.colors.error),
                  title: Text(ctx.tr('Remover fotografia'), style: TextStyle(color: ctx.colors.error)),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    final auth = ref.read(authRepositoryProvider);
    if (action == 'remove') {
      setState(() => _busy = true);
      await runGuarded(context, () => auth.updatePhoto(null), success: tr('Fotografia removida.'));
    } else {
      PickedImage? picked;
      try {
        // Pequena e quadrada o suficiente para os avatares (até 2 MB no servidor).
        picked = await pickChatImage(action == 'camera' ? ImageSource.camera : ImageSource.gallery, maxSide: 640);
      } catch (_) {
        if (mounted) {
          showMessage(context, context.tr('Não foi possível aceder às fotografias. Verifica as permissões.'));
        }
        return;
      }
      if (picked == null || !mounted) return;
      setState(() => _busy = true);
      final bytes = picked.bytes;
      await runGuarded(context, () => auth.updatePhoto(bytes), success: tr('Fotografia atualizada.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    const size = 64.0;
    return Semantics(
      button: true,
      label: context.tr('Alterar fotografia de perfil'),
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
    if (a.highContrast) tr('contraste'),
    if (a.reduceMotion) tr('sem animações'),
  ];
  return parts.isEmpty ? tr('Do telemóvel') : parts.join(', ');
}

/// Tema de cor da app (Birthdayly+).
Future<void> _pickAccent(BuildContext context, WidgetRef ref) async {
  if (!await requirePlus(context, ref, feature: context.tr('Mudar o tema'))) return;
  if (!context.mounted) return;
  final current = ref.read(themeAccentProvider);
  final picked = await showModalBottomSheet<AppAccent>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        // Desliza quando não cabe (letra grande).
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(ctx.tr('Tema'), style: AppTheme.display(ctx, size: 22)),
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
    ),
  );
  if (picked != null) ref.read(themeAccentProvider.notifier).set(picked);
}

Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
  final current = ref.read(localeProvider);
  final picked = await showModalBottomSheet<(Locale?,)>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        // Desliza quando não cabe (letra grande).
        child: RadioGroup<String>(
          groupValue: current == null ? '' : Translations.tagOf(current),
          onChanged: (tag) => Navigator.pop(ctx, (tag == null || tag.isEmpty ? null : Translations.localeOf(tag),)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(ctx.tr(Keys.settingsLanguage), style: AppTheme.display(ctx, size: 22)),
              ),
              RadioListTile<String>(
                value: '',
                title: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Icon(LucideIcons.smartphone, size: 20, color: ctx.palette.mutedForeground),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(ctx.tr(Keys.settingsLanguageSystem))),
                  ],
                ),
              ),
              for (final code
                  in Translations.languageCodes.toList()..sort(
                    (a, b) =>
                        foldText(Translations.languageNames[a]!).compareTo(foldText(Translations.languageNames[b]!)),
                  ))
                RadioListTile<String>(
                  value: code,
                  title: Row(
                    children: [
                      CountryFlag.fromCountryCode(
                        Translations.languageFlags[code]!,
                        theme: const ImageTheme(width: 28, height: 20, shape: RoundedRectangle(4)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(Translations.languageNames[code]!)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
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
          Text(context.tr('O teu nome'), style: AppTheme.display(context, size: 22)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: Text(context.tr('Guardar'))),
        ],
      ),
    );
  }
}
