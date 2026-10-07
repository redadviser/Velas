import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../core/utils/identity.dart';
import '../../services/notification_service.dart';
import 'identity_sheets.dart';
import '../auth/reset_password_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, UserProfile profile) =>
      runGuarded(context, () => ref.read(authRepositoryProvider).updateProfile(profile));

  Future<void> _editName(BuildContext context, WidgetRef ref, UserProfile user) async {
    final ctrl = TextEditingController(text: user.name);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('O teu nome', style: AppTheme.display(ctx, size: 22)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    ctrl.dispose();
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

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final json = const JsonEncoder.withIndent('  ').convert(ref.read(dataProvider).toExportJson());
    await SharePlus.instance.share(ShareParams(text: json, subject: 'Os meus dados — Velas'));
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
              CircleAvatar(
                radius: 32,
                backgroundColor: context.palette.accent,
                child: Text(
                  user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                  style: AppTheme.display(context, size: 26, color: context.palette.accentForeground),
                ),
              ),
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
                title: 'Dados de pagamento',
                value: [
                  if (user.payment.mbwayPhone.isNotEmpty) 'MB WAY',
                  if (user.payment.iban.isNotEmpty) 'IBAN',
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
                icon: LucideIcons.tag,
                title: 'Categorias',
                value: '${data.categories.length}',
                onTap: () => context.push('/profile/categories'),
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
              _Tile(icon: LucideIcons.download, title: 'Exportar os meus dados', onTap: () => _export(context, ref)),
              _Tile(
                icon: LucideIcons.trash2,
                title: 'Eliminar conta',
                destructive: true,
                onTap: () => _deleteAccount(context, ref),
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
              'Velas · versão 1.0.0',
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
