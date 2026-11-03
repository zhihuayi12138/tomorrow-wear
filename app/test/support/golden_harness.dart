import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingtian_chuanshenme/state/providers.dart';
import 'package:mingtian_chuanshenme/theme.dart';

import 'fake_repository.dart';

/// golden 里要自己装两套字体，否则汉字和图标全是方块：
/// 1. `flutter test` 会传 `--use-test-fonts`，默认字体是 Ahem（每个字都是实心方块），
///    所以装一个真黑体并让主题显式使用它（[kGoldenFontFamily]）。
/// 2. 同一个命令行还会传 `--disable-asset-fonts`，MaterialIcons 也不在 → 手动装。
const kGoldenFontFamily = 'SimHei';

Future<void> loadCjkFont() async {
  const candidates = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simsun.ttc',
  ];
  var ok = false;
  for (final path in candidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    // 除了主题用的家族名，再顶替一下 Roboto 和 Ahem —— 有些地方写死了
    // `TextStyle(fontSize: 13)` 这种不带家族的样式，会回落到 Flutter 测试环境
    // 的默认家族 Ahem（每个字都是实心方块），不注册就在那些地方出现方块。
    for (final family in const [kGoldenFontFamily, 'Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    ok = true;
    break;
  }
  if (!ok) fail('找不到中文字体，golden 里会全是方块');

  // 图标字体：位置随引擎版本变化，按几个常见路径找。
  const iconCandidates = [
    r'D:\flutter_sdk\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    r'D:\flutter_sdk\flutter\packages\flutter\lib\src\material\fonts\MaterialIcons-Regular.otf',
  ];
  for (final path in iconCandidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    return;
  }
  fail('找不到 MaterialIcons 字体，图标会全是方块');
}

/// 统一的截图入口：固定 390×844 @2x，pump 若干次让 Future 和图片解码落地。
Future<void> pumpScreen(
  WidgetTester tester,
  Widget widget, {
  required FakeRepository repo,
  Size size = const Size(390, 844),
  double dpr = 2.0,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.build(fontFamily: kGoldenFontFamily),
        debugShowCheckedModeBanner: false,
        home: widget,
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  // 关键：`Image.memory` 的解码是真实异步的，`pump` 的假时钟推不动它。
  // 不跑 runAsync 的话，golden 里所有图都是空的（第一版就是这么踩的）。
  await tester.runAsync(() async {
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 3; i++)
        Future<void>.delayed(const Duration(milliseconds: 80)),
    ]);
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

// ---------------------------------------------------------------------------
// 假图片生成
// ---------------------------------------------------------------------------

enum GarmentShape { tee, hoodie, pants, dress, shoe, coat }

const _palette = <int>[
  0xFF4A4A4A, // 炭黑
  0xFF8C6A4F, // 驼
  0xFF6E7B8B, // 灰蓝
  0xFFB9C0B6, // 雾绿
  0xFFD8CFC4, // 米
  0xFF7A4A4A, // 酒红
  0xFFF0EDE8, // 近白
  0xFF3B4A5A, // 藏蓝
];

/// 平铺图：纯色衣物剪影 + 浅灰底，模拟抠图前的样子。
Uint8List fakeFlat({
  GarmentShape shape = GarmentShape.tee,
  int paletteIndex = 0,
  bool deepTile = false,
}) {
  const w = 600;
  const h = 600;
  final bytes = Uint8List(w * h * 4);
  final bg = deepTile ? 0xD8 : 0xF4;
  var o = 0;
  for (var y = 0; y < h; y++) {
    // 极轻微的纵向渐变，避免大片纯色看起来像渲染失败的占位块
    final v = (bg - (y * 8 ~/ h)).clamp(0, 255);
    for (var x = 0; x < w; x++) {
      bytes[o++] = v;
      bytes[o++] = v;
      bytes[o++] = (v - 2).clamp(0, 255);
      bytes[o++] = 255;
    }
  }

  final color = _palette[paletteIndex % _palette.length];
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;

  for (final poly in _shapePolygons(shape)) {
    _fillPolygon(bytes, w, h, poly, r, g, b);
  }
  return _encodePng(bytes, w, h);
}

/// 上身图：暖灰墙面 + 人形剪影 + 衣服色块。
Uint8List fakeWorn({int seed = 0}) {
  const w = 480;
  const h = 600;
  final bytes = Uint8List(w * h * 4);
  var o = 0;
  for (var y = 0; y < h; y++) {
    final t = y / h;
    final base = (222 - t * 38 + (seed % 5) * 2).round().clamp(0, 255);
    for (var x = 0; x < w; x++) {
      bytes[o++] = base;
      bytes[o++] = (base - 6).clamp(0, 255);
      bytes[o++] = (base - 16).clamp(0, 255);
      bytes[o++] = 255;
    }
  }
  const skin = 0xFFD2BAA8;
  // 头、肩、腿：用几段椭圆糊成一个粗略剪影
  _fillEllipse(bytes, w, h, w ~/ 2, 150, 46, 58, (skin >> 16) & 0xFF,
      (skin >> 8) & 0xFF, skin & 0xFF);
  _fillEllipse(bytes, w, h, w ~/ 2, 560, 110, 120, (skin >> 16) & 0xFF,
      (skin >> 8) & 0xFF, skin & 0xFF);
  // 衣服
  final cloth = _palette[seed % _palette.length];
  _fillEllipse(bytes, w, h, w ~/ 2, 380, 130, 165, (cloth >> 16) & 0xFF,
      (cloth >> 8) & 0xFF, cloth & 0xFF);
  return _encodePng(bytes, w, h);
}

List<List<Offset>> _shapePolygons(GarmentShape shape) {
  // 坐标基于 600×600，衣物落在中间，四周留白
  switch (shape) {
    case GarmentShape.tee:
      return [
        [
          const Offset(180, 160),
          const Offset(250, 130),
          const Offset(350, 130),
          const Offset(420, 160),
          const Offset(470, 230),
          const Offset(415, 265),
          const Offset(390, 235),
          const Offset(400, 470),
          const Offset(200, 470),
          const Offset(210, 235),
          const Offset(185, 265),
          const Offset(130, 230),
        ],
      ];
    case GarmentShape.hoodie:
      return [
        [
          const Offset(170, 175),
          const Offset(430, 175),
          const Offset(455, 250),
          const Offset(405, 270),
          const Offset(410, 490),
          const Offset(190, 490),
          const Offset(195, 270),
          const Offset(145, 250),
        ],
        [
          const Offset(240, 120),
          const Offset(360, 120),
          const Offset(340, 175),
          const Offset(260, 175),
        ],
      ];
    case GarmentShape.pants:
      return [
        [
          const Offset(215, 130),
          const Offset(385, 130),
          const Offset(378, 480),
          const Offset(325, 480),
          const Offset(300, 260),
          const Offset(275, 480),
          const Offset(222, 480),
        ],
      ];
    case GarmentShape.dress:
      return [
        [
          const Offset(255, 120),
          const Offset(345, 120),
          const Offset(370, 200),
          const Offset(455, 480),
          const Offset(145, 480),
          const Offset(230, 200),
        ],
      ];
    case GarmentShape.shoe:
      return [
        [
          const Offset(150, 340),
          const Offset(230, 270),
          const Offset(330, 285),
          const Offset(430, 350),
          const Offset(430, 400),
          const Offset(155, 400),
        ],
      ];
    case GarmentShape.coat:
      return [
        [
          const Offset(190, 150),
          const Offset(270, 120),
          const Offset(330, 120),
          const Offset(410, 150),
          const Offset(455, 240),
          const Offset(410, 265),
          const Offset(425, 500),
          const Offset(175, 500),
          const Offset(190, 265),
          const Offset(145, 240),
        ],
      ];
  }
}

void _fillPolygon(
  Uint8List bytes,
  int w,
  int h,
  List<Offset> poly,
  int r,
  int g,
  int b,
) {
  var minY = double.infinity;
  var maxY = 0.0;
  for (final p in poly) {
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final y0 = minY.floor().clamp(0, h - 1);
  final y1 = maxY.ceil().clamp(0, h - 1);
  for (var y = y0; y <= y1; y++) {
    final xs = <double>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final c = poly[(i + 1) % poly.length];
      if ((a.dy <= y && c.dy > y) || (c.dy <= y && a.dy > y)) {
        xs.add(a.dx + (y - a.dy) / (c.dy - a.dy) * (c.dx - a.dx));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      final xa = xs[i].round().clamp(0, w - 1);
      final xb = xs[i + 1].round().clamp(0, w - 1);
      for (var x = xa; x <= xb; x++) {
        final o = (y * w + x) * 4;
        bytes[o] = r;
        bytes[o + 1] = g;
        bytes[o + 2] = b;
        bytes[o + 3] = 255;
      }
    }
  }
}

void _fillEllipse(
  Uint8List bytes,
  int w,
  int h,
  int cx,
  int cy,
  int rx,
  int ry,
  int r,
  int g,
  int b,
) {
  for (var y = (cy - ry).clamp(0, h - 1); y <= (cy + ry).clamp(0, h - 1); y++) {
    for (var x = (cx - rx).clamp(0, w - 1);
        x <= (cx + rx).clamp(0, w - 1);
        x++) {
      final dx = (x - cx) / rx;
      final dy = (y - cy) / ry;
      if (dx * dx + dy * dy > 1) continue;
      final o = (y * w + x) * 4;
      bytes[o] = r;
      bytes[o + 1] = g;
      bytes[o + 2] = b;
      bytes[o + 3] = 255;
    }
  }
}

/// 自己编 PNG，避免依赖 image 包编码器（golden 想快且不受依赖升级影响）。
Uint8List _encodePng(Uint8List rgba, int w, int h) {
  final raw = Uint8List(h * (w * 4 + 1));
  var o = 0;
  for (var y = 0; y < h; y++) {
    raw[o++] = 0; // filter: none
    raw.setRange(o, o + w * 4, rgba, y * w * 4);
    o += w * 4;
  }
  final compressed = _zlib(raw);
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', compressed);
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final t = Uint8List.fromList(type.codeUnits);
  out.add(t);
  out.add(data);
  var crc = 0xFFFFFFFF;
  crc = _crc32(crc, t);
  crc = _crc32(crc, data);
  final c = ByteData(4)..setUint32(0, crc ^ 0xFFFFFFFF);
  out.add(c.buffer.asUint8List());
}

int _crc32(int crc, Uint8List data) {
  var c = crc;
  for (final byte in data) {
    c ^= byte;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
  }
  return c & 0xFFFFFFFF;
}

/// 极简 zlib（stored 模式，不压缩），只为了让 PNG 合法。
Uint8List _zlib(Uint8List data) {
  final out = BytesBuilder();
  out.add([0x78, 0x01]);
  var offset = 0;
  while (offset < data.length) {
    final chunk = math.min(65535, data.length - offset);
    final last = offset + chunk >= data.length ? 1 : 0;
    out.addByte(last);
    out.addByte(chunk & 0xFF);
    out.addByte((chunk >> 8) & 0xFF);
    out.addByte((chunk & 0xFF) ^ 0xFF);
    out.addByte(((chunk >> 8) & 0xFF) ^ 0xFF);
    out.add(data.sublist(offset, offset + chunk));
    offset += chunk;
  }
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final adler = (b << 16) | a;
  out.add([
    (adler >> 24) & 0xFF,
    (adler >> 16) & 0xFF,
    (adler >> 8) & 0xFF,
    adler & 0xFF,
  ]);
  return out.toBytes();
}
