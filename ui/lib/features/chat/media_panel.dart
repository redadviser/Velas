import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import 'chat_widgets.dart';

enum MediaTab { emoji, gifs, stickers }

/// Painel por baixo da caixa de texto: emojis, GIFs e stickers.
class MediaPanel extends StatefulWidget {
  const MediaPanel({
    super.key,
    required this.initialTab,
    required this.textController,
    required this.onGif,
    required this.onSticker,
    this.height = 300,
  });

  final MediaTab initialTab;
  final TextEditingController textController;
  final void Function(Gif gif, {required bool asSticker}) onGif;
  final ValueChanged<Sticker> onSticker;
  final double height;

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.index);

  @override
  void didUpdateWidget(MediaPanel old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _tabs.animateTo(widget.initialTab.index);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            dividerHeight: 0,
            labelStyle: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(height: 40, text: 'Emoji'),
              Tab(height: 40, text: 'GIFs'),
              Tab(height: 40, text: 'Stickers'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _EmojiTab(controller: widget.textController),
                GifSearch(kind: GifKind.gifs, onPick: (g) => widget.onGif(g, asSticker: false)),
                _StickersTab(onSticker: widget.onSticker, onGiphySticker: (g) => widget.onGif(g, asSticker: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Configuração do seletor de emojis com as cores da app.
Config emojiConfig(BuildContext context, {double? height}) {
  final bg = context.palette.card;
  final primary = context.colors.primary;
  final muted = context.palette.mutedForeground;
  return Config(
    height: height,
    locale: const Locale('pt'),
    checkPlatformCompatibility: true,
    emojiViewConfig: EmojiViewConfig(
      backgroundColor: bg,
      columns: 8,
      emojiSizeMax: 28 * (foundation.defaultTargetPlatform == TargetPlatform.iOS ? 1.2 : 1.0),
      noRecents: Text('Ainda sem recentes', style: TextStyle(color: muted)),
    ),
    categoryViewConfig: CategoryViewConfig(
      backgroundColor: bg,
      indicatorColor: primary,
      iconColorSelected: primary,
      iconColor: muted,
      backspaceColor: primary,
    ),
    bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
    searchViewConfig: SearchViewConfig(backgroundColor: bg, hintText: 'Procurar emoji'),
    skinToneConfig: SkinToneConfig(dialogBackgroundColor: bg, indicatorColor: muted),
  );
}

class _EmojiTab extends StatelessWidget {
  const _EmojiTab({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => EmojiPicker(textEditingController: controller, config: emojiConfig(context));
}

/// Pesquisa de GIFs ou stickers no GIPHY, com os populares sem pesquisa.
class GifSearch extends ConsumerStatefulWidget {
  const GifSearch({super.key, required this.kind, required this.onPick});

  final GifKind kind;
  final ValueChanged<Gif> onPick;

  @override
  ConsumerState<GifSearch> createState() => _GifSearchState();
}

class _GifSearchState extends ConsumerState<GifSearch> with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<Gif> _results = const [];
  int? _next = 0;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final repo = ref.read(chatRepositoryProvider);
    if (repo == null) return;
    if (reset) {
      _generation++;
      setState(() {
        _results = const [];
        _next = 0;
        _error = null;
      });
    }
    if (_loading || _next == null) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await repo.searchGifs(widget.kind, _query.text, offset: _next!);
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = [..._results, ...page.results];
        _next = page.nextOffset;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stickers = widget.kind == GifKind.stickers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: stickers ? 'Procurar stickers' : 'Procurar GIFs (ex.: parabéns)',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
            ),
          ),
        ),
        Expanded(
          child: _error != null && _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.palette.mutedForeground),
                    ),
                  ),
                )
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: stickers ? 4 : 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _results.length + (_loading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _results.length) {
                      return const Center(
                        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final g = _results[i];
                    return GestureDetector(
                      onTap: () => widget.onPick(g),
                      onLongPress: () => runGuarded(
                        context,
                        () => ref.read(stickersProvider.notifier).saveFromGif(g),
                        success: 'Guardado nos teus stickers.',
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ChatImage(url: g.previewUrl, fit: stickers ? BoxFit.contain : BoxFit.cover),
                      ),
                    );
                  },
                ),
        ),
        // Exigido pelos termos do GIPHY.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Powered by GIPHY',
            style: context.text.labelSmall?.copyWith(
              color: context.palette.mutedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StickersTab extends ConsumerStatefulWidget {
  const _StickersTab({required this.onSticker, required this.onGiphySticker});

  final ValueChanged<Sticker> onSticker;
  final ValueChanged<Gif> onGiphySticker;

  @override
  ConsumerState<_StickersTab> createState() => _StickersTabState();
}

class _StickersTabState extends ConsumerState<_StickersTab> {
  bool _mine = true;

  Future<void> _addFromGallery() async {
    final picked = await pickChatImage(ImageSource.gallery, maxSide: 512).catchError((_) => null);
    if (picked == null || !mounted) return;
    await runGuarded(
      context,
      () => ref.read(stickersProvider.notifier).upload(picked.bytes, width: picked.width, height: picked.height),
      success: 'Sticker criado.',
    );
  }

  Future<void> _manage(Sticker s) async {
    final ok = await confirmDialog(
      context,
      title: 'Apagar sticker?',
      message: 'Deixa de aparecer nos teus stickers.',
      confirm: 'Apagar',
    );
    if (ok && mounted) await runGuarded(context, () => ref.read(stickersProvider.notifier).delete(s));
  }

  @override
  Widget build(BuildContext context) {
    final stickers = ref.watch(stickersProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Os meus')),
              ButtonSegment(value: false, label: Text('Procurar')),
            ],
            selected: {_mine},
            onSelectionChanged: (s) => setState(() => _mine = s.first),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        Expanded(
          child: !_mine
              ? GifSearch(kind: GifKind.stickers, onPick: widget.onGiphySticker)
              : switch (stickers) {
                  AsyncError(:final error) => Center(child: Text(friendlyError(error))),
                  AsyncData(:final value) || AsyncLoading(:final value?) => GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: value.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Material(
                          color: context.palette.muted,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _addFromGallery,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.imagePlus, color: context.palette.mutedForeground),
                                const SizedBox(height: 4),
                                Text(
                                  'Criar',
                                  style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final s = value[i - 1];
                      return GestureDetector(
                        onTap: () => widget.onSticker(s),
                        onLongPress: () => _manage(s),
                        child: ChatImage(url: s.url, fit: BoxFit.contain),
                      );
                    },
                  ),
                  _ => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                },
        ),
        if (_mine && (stickers.value?.isEmpty ?? false))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Mantém o dedo numa imagem, GIF ou sticker da conversa para o guardares aqui.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ),
      ],
    );
  }
}
