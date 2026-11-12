import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets/common.dart';

/// Aberto a partir do link de convite de uma festa: entra e abre-a.
class JoinPartyScreen extends ConsumerStatefulWidget {
  const JoinPartyScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinPartyScreen> createState() => _JoinPartyScreenState();
}

class _JoinPartyScreenState extends ConsumerState<JoinPartyScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    setState(() => _error = null);
    try {
      final party = await ref.read(partiesProvider.notifier).run((repo) => repo.join(widget.code));
      if (mounted && party != null) context.go('/parties/${party.id}');
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _error == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : ErrorRetry(error: _error!, onRetry: _join),
    );
  }
}
