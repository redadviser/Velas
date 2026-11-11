import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/wishlist_providers.dart';
import '../gifts/wishlist_widgets.dart';

/// Os meus gostos e a minha lista de desejos (o que os amigos veem).
class MyWishlistScreen extends ConsumerWidget {
  const MyWishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    final online = ref.watch(apiClientProvider) != null;
    final wishes = ref.watch(myWishlistProvider);
    final muted = context.palette.mutedForeground;
    return Scaffold(
      appBar: AppBar(title: const Text('Gostos e desejos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            online
                ? 'Os teus amigos veem isto no teu perfil, para acertarem na prenda. Mais ninguém vê.'
                : 'Ajuda-te a ti e, com conta, aos teus amigos a acertar na prenda.',
            style: context.text.bodyMedium?.copyWith(color: muted),
          ),
          const SectionTitle('Gostos e hobbies', padding: EdgeInsets.fromLTRB(4, 20, 0, 10)),
          InterestPicker(
            selected: user.interests,
            onChanged: (keys) => runGuarded(
              context,
              () => ref.read(authRepositoryProvider).updateProfile(user.copyWith(interests: keys)),
            ),
          ),
          if (online) ...[
            SectionTitle(
              'A minha lista de desejos',
              action: 'Adicionar',
              onAction: () => showWishEditor(context),
              padding: const EdgeInsets.fromLTRB(4, 28, 0, 6),
            ),
            switch (wishes) {
              AsyncData(:final value) when value.isEmpty => DashedButton(
                icon: LucideIcons.plus,
                label: 'Junta o primeiro desejo',
                onTap: () => showWishEditor(context),
              ),
              AsyncData(:final value) => AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, w) in value.indexed) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      WishRow(
                        item: w,
                        onTap: () => showWishEditor(context, item: w),
                      ),
                    ],
                  ],
                ),
              ),
              AsyncError(:final error) => ErrorRetry(error: error, onRetry: () => ref.invalidate(myWishlistProvider)),
              _ => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ],
      ),
    );
  }
}
