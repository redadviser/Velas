// Gera o ícone da app (o "b-vela") em todos os tamanhos de iOS e Android.
//
//   flutter test tool/generate_app_icon.dart
//
// O desenho segue o SVG de assets/branding/app_icon.svg (quadrado de 100 × 100).
// O ícone adaptável do Android, o monocromático e o das notificações são
// vetores em android/app/src/main/res/drawable (não são gerados aqui).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _coral = Color(0xFFF05560);
const _pink = Color(0xFFE662A8);
const _lavender = Color(0xFFAB8BE3);
const _flame = Color(0xFFFFF3D6);
const _flameIn = Color(0xFFF4A25C);

/// Desenha o ícone num quadrado de [size] px. Com [radius] (fração do lado),
/// os cantos ficam arredondados e transparentes.
void paintAppIcon(Canvas canvas, double size, {double radius = 0}) {
  canvas.save();
  canvas.scale(size / 100);
  final square = const Rect.fromLTWH(0, 0, 100, 100);
  if (radius > 0) canvas.clipRRect(RRect.fromRectAndRadius(square, Radius.circular(100 * radius)));
  canvas.drawRect(
    square,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(100, 100), [_coral, _pink, _lavender], [0, .55, 1]),
  );

  final white = Paint()..color = Colors.white;
  // Chama: gota exterior e interior.
  canvas.drawPath(
    Path()
      ..moveTo(33, 11)
      ..cubicTo(38.5, 18, 40, 22, 40, 25.5)
      ..arcToPoint(const Offset(26, 25.5), radius: const Radius.circular(7))
      ..cubicTo(26, 22, 27.5, 18, 33, 11)
      ..close(),
    Paint()..color = _flame,
  );
  canvas.drawPath(
    Path()
      ..moveTo(33, 18.5)
      ..cubicTo(35.6, 22, 36.3, 24, 36.3, 25.6)
      ..arcToPoint(const Offset(29.7, 25.6), radius: const Radius.circular(3.3))
      ..cubicTo(29.7, 24, 30.4, 22, 33, 18.5)
      ..close(),
    Paint()..color = _flameIn,
  );
  // Pavio, vela (a haste do "b") e a barriga do "b".
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 33, 2, 4), const Radius.circular(1)), white);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 37, 12, 48), const Radius.circular(4)), white);
  canvas.drawCircle(
    const Offset(54, 66),
    15,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12,
  );
  canvas.restore();
}

Future<Uint8List> _render(int px, {double radius = 0}) async {
  final recorder = ui.PictureRecorder();
  paintAppIcon(Canvas(recorder), px.toDouble(), radius: radius);
  final image = await recorder.endRecording().toImage(px, px);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  // Sem cantos transparentes, grava-se sem canal alfa (a App Store recusa-o).
  return _png(px, px, rgba, alpha: radius > 0);
}

// PNG mínimo (RGB ou RGBA, 8 bits, sem filtro), para controlar o canal alfa.
Uint8List _png(int w, int h, Uint8List rgba, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      raw.add(rgba.sublist(i, i + channels));
    }
  }
  final out = BytesBuilder()..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = [...ascii.encode(type), ...data];
    out
      ..add(_u32(data.length))
      ..add(typed)
      ..add(_u32(_crc32(typed)));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, alpha ? 6 : 2, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder(level: 9).convert(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gera o ícone da app', () async {
    // iOS: todos os tamanhos do AppIcon.appiconset, quadrados cheios (o sistema arredonda).
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final contents = jsonDecode(File('$ios/Contents.json').readAsStringSync()) as Map;
    for (final img in (contents['images'] as List).cast<Map>()) {
      final pt = double.parse((img['size'] as String).split('x').first);
      final scale = int.parse((img['scale'] as String).replaceAll('x', ''));
      File('$ios/${img['filename']}').writeAsBytesSync(await _render((pt * scale).round()));
    }

    // Android antes do 8.0 (sem ícone adaptável): cantos arredondados.
    const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final e in legacy.entries) {
      File('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png').writeAsBytesSync(await _render(e.value, radius: .22));
    }

    // Para as lojas: App Store (1024, sem alfa) e Google Play (512).
    Directory('assets/branding').createSync(recursive: true);
    File('assets/branding/app_icon_1024.png').writeAsBytesSync(await _render(1024));
    File('assets/branding/play_store_512.png').writeAsBytesSync(await _render(512));
  });
}
