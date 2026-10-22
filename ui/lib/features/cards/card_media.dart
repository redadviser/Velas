import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/card_models.dart';
import '../chat/chat_widgets.dart';

/// Ficheiro escolhido para um cartão especial, antes de ser carregado.
typedef PickedCardMedia = ({CardMediaKind kind, Uint8List bytes, String? path});

/// Limite do servidor (PhotoStorage.mediaMaxBytes).
const _maxBytes = 25 * 1024 * 1024;

/// Escolher a fotografia, o vídeo ou gravar o áudio. `null` se desistiu.
Future<PickedCardMedia?> pickCardMedia(BuildContext context, CardMediaKind kind) async {
  try {
    switch (kind) {
      case CardMediaKind.image:
        final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        return f == null ? null : (kind: kind, bytes: await f.readAsBytes(), path: f.path);
      case CardMediaKind.video:
        final source = await _videoSource(context);
        if (source == null) return null;
        final f = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 30));
        if (f == null) return null;
        final bytes = await f.readAsBytes();
        if (bytes.length > _maxBytes) {
          if (context.mounted) showMessage(context, 'O vídeo é grande demais. Escolhe um até 30 segundos.');
          return null;
        }
        return (kind: kind, bytes: bytes, path: f.path);
      case CardMediaKind.audio:
        if (!context.mounted) return null;
        return showModalBottomSheet<PickedCardMedia>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => const _AudioRecorderSheet(),
        );
    }
  } catch (_) {
    if (context.mounted) showMessage(context, 'Não foi possível aceder à câmara, à galeria ou ao microfone. Verifica as permissões.');
    return null;
  }
}

Future<ImageSource?> _videoSource(BuildContext context) => showModalBottomSheet<ImageSource>(
  context: context,
  builder: (ctx) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(LucideIcons.video),
          title: const Text('Gravar um vídeo'),
          subtitle: const Text('Até 30 segundos'),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(LucideIcons.film),
          title: const Text('Escolher da galeria'),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// Gravar uma mensagem de voz (até 60 segundos, AAC em .m4a).
class _AudioRecorderSheet extends StatefulWidget {
  const _AudioRecorderSheet();

  @override
  State<_AudioRecorderSheet> createState() => _AudioRecorderSheetState();
}

class _AudioRecorderSheetState extends State<_AudioRecorderSheet> {
  static const _limit = Duration(seconds: 60);

  final _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  String? _path;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) showMessage(context, 'Permite o acesso ao microfone para gravar.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/cartao-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
      _path = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= _limit) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (mounted) {
      setState(() {
        _recording = false;
        _path = path;
      });
    }
  }

  Future<void> _use() async {
    final path = _path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (mounted) Navigator.pop(context, (kind: CardMediaKind.audio, bytes: bytes, path: path));
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mensagem de voz', textAlign: TextAlign.center, style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 6),
            Text(
              _recording ? 'A gravar… ${_fmt(_elapsed)} de ${_fmt(_limit)}' : 'Até ${_limit.inSeconds} segundos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            Center(
              child: GestureDetector(
                onTap: _recording ? _stop : _start,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(gradient: context.palette.brand, shape: BoxShape.circle),
                  child: Icon(_recording ? LucideIcons.square : LucideIcons.mic, color: Colors.white, size: 30),
                ),
              ),
            ),
            if (_path != null && !_recording) ...[
              const SizedBox(height: 16),
              CardMediaView(media: (kind: CardMediaKind.audio, url: _path!)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _use, child: const Text('Usar esta gravação')),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: () async {
                if (_recording) await _recorder.stop();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mostra a fotografia, o vídeo (toca ao tocar) ou o áudio (botão de play) de um
/// cartão. [CardMedia.url] pode ser um URL ou um caminho local (antes de enviar).
class CardMediaView extends StatelessWidget {
  const CardMediaView({super.key, required this.media});

  final CardMedia media;

  @override
  Widget build(BuildContext context) {
    return switch (media.kind) {
      CardMediaKind.image => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ChatImage(url: media.url, fit: BoxFit.cover),
      ),
      CardMediaKind.video => _VideoView(url: media.url),
      CardMediaKind.audio => _AudioView(url: media.url),
    };
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.url});

  final String url;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _c = widget.url.startsWith('http')
      ? VideoPlayerController.networkUrl(Uri.parse(widget.url))
      : VideoPlayerController.file(File(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _c.value.isInitialized;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: ready ? _c.value.aspectRatio : 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black, child: ready ? VideoPlayer(_c) : const SizedBox()),
            if (_failed)
              const Center(child: Icon(LucideIcons.videoOff, color: Colors.white70))
            else
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: !ready ? null : () => _c.value.isPlaying ? _c.pause() : _c.play(),
                  child: Center(
                    child: _c.value.isPlaying
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
                            child: ready
                                ? const Icon(LucideIcons.play, color: Colors.white, size: 28)
                                : const SizedBox.square(
                                    dimension: 28,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AudioView extends StatefulWidget {
  const _AudioView({required this.url});

  final String url;

  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }))
      ..add(_player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }))
      ..add(_player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) return _player.pause();
    final source = widget.url.startsWith('http') ? UrlSource(widget.url) : DeviceFileSource(widget.url);
    await _player.play(source);
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(color: context.palette.accent, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? LucideIcons.pause : LucideIcons.play, color: context.colors.primary),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 4,
                backgroundColor: context.palette.border,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _fmt(_duration == Duration.zero ? _position : _duration - _position),
            style: context.text.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
