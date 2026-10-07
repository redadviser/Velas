import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../providers.dart';
import 'common.dart';

/// Mostra carregamento/erro até os dados do utilizador estarem disponíveis.
class DataGate extends ConsumerWidget {
  const DataGate({super.key, required this.builder});

  final Widget Function(BuildContext context, AppData data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    final data = async.value;
    if (data != null && data.loaded) return builder(context, data);
    if (async.hasError) {
      return ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(appDataProvider));
    }
    return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
  }
}

Future<void> refreshData(WidgetRef ref) async {
  try {
    await ref.read(dataRepositoryProvider)?.load();
  } catch (_) {
    // O erro é visível no estado do provider; aqui só se evita o crash.
  }
}
