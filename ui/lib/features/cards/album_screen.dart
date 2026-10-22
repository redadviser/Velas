import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/cards_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/card_models.dart';
import '../chat/chat_widgets.dart';
import '../profile/plus.dart';

/// Fotografia que a pessoa acrescentou ao próprio mural (GET /wall/photos).
typedef WallPhoto = ({String id, String url, String caption});

final wallPhotosProvider = FutureProvider.autoDispose.family<List<WallPhoto>, int>((ref, year) async {
  final api = ref.watch(apiClientProvider);
  if (api == null) return const [];
  final rows = (await api.get('/wall/photos?year=$year')) as List;
  return [
    for (final r in rows.cast<Map>())
      (id: r['id'] as String, url: r['url'] as String, caption: r['caption'] as String? ?? ''),
  ];
});

/// O álbum de um ano (Birthdayly+): as fotografias dos cartões recebidos e as
/// que a pessoa acrescentou (a festa, o bolo, a prenda).
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.year});

  final int year;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  bool _uploading = false;

  Future<void> _add() async {
    if (!await requirePlus(context, ref, feature: 'O álbum do mural')) return;
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: 10);
    } catch (_) {
      if (mounted) showMessage(context, 'Não foi possível aceder às fotografias. Verifica as permissões.');
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    await runGuarded(context, () async {
      for (final f in files) {
        await api.postBytes('/wall/photos?year=${widget.year}', await f.readAsBytes(), 'image/jpeg');
      }
    }, success: files.length == 1 ? 'Fotografia acrescentada.' : '${files.length} fotografias acrescentadas.');
    if (!mounted) return;
    setState(() => _uploading = false);
    ref.invalidate(wallPhotosProvider(widget.year));
  }

  Future<void> _remove(WallPhoto p) async {
    final ok = await confirmDialog(context, title: 'Tirar do álbum?', message: 'A fotografia é apagada do teu mural.', confirm: 'Tirar');
    if (!ok || !mounted) return;
    await runGuarded(context, () => ref.read(apiClientProvider)!.delete('/wall/photos/${p.id}'));
    ref.invalidate(wallPhotosProvider(widget.year));
  }

  @override
  Widget build(BuildContext context) {
    final cardPhotos = [
      for (final c in ref.watch(wallProvider).value ?? const <ReceivedCard>[])
        if (c.receivedAt.year == widget.year && c.media?.kind == CardMediaKind.image) (url: c.media!.url, from: c.sender.firstName),
    ];
    final photos = ref.watch(wallPhotosProvider(widget.year));
    final mine = photos.value ?? const <WallPhoto>[];
    final empty = cardPhotos.isEmpty && mine.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('Álbum de ${widget.year}')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-album',
        onPressed: _uploading ? null : _add,
        icon: _uploading
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(LucideIcons.imagePlus),
        label: const Text('Acrescentar'),
      ),
      body: photos.isLoading && empty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : empty
          ? const EmptyState(
              icon: LucideIcons.images,
              title: 'O álbum ainda está vazio',
              message: 'As fotografias dos cartões que receberes aparecem aqui. Acrescenta também as da festa.',
            )
          : GridView.count(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final p in mine)
                  _Tile(
                    url: p.url,
                    title: p.caption.isEmpty ? 'O meu mural' : p.caption,
                    onLongPress: () => _remove(p),
                  ),
                for (final c in cardPhotos) _Tile(url: c.url, title: 'De ${c.from}', badge: c.from),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.url, required this.title, this.badge, this.onLongPress});

  final String url;
  final String title;
  final String? badge;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ZoomablePhoto(
        url: url,
        title: title,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ChatImage(url: url),
              if (badge != null)
                Positioned(
                  left: 6,
                  bottom: 6,
                  right: 6,
                  child: Text(
                    badge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: context.palette.mutedForeground, blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
