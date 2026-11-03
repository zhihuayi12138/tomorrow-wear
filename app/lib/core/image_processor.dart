import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 统一排版与主色提取。规则见 `设计文档.md` §5.5 与 §5.4。
///
/// 这里的函数都是纯函数、无 IO，因此可以安全地丢进 Isolate。

class Rgb {
  final int r, g, b;
  const Rgb(this.r, this.g, this.b);

  /// 打包成 0xRRGGBB，方便测试与预览直接比对。
  int get value => (r << 16) | (g << 8) | b;
}

/// 平铺图的底色方案。
///
/// 每一档都有「浅一档」和「深一档」两个色：浅色衣物（白、米、浅灰）如果
/// 铺在浅底色上会连轮廓都看不出来，所以前景平均亮度 > 0.85 时自动换深一档。
/// 见设计文档 §5.5。
class TileOption {
  final String key;
  final String label;

  /// 给设置页的小字说明：这一档适合什么情况。
  final String hint;
  final Rgb normal;
  final Rgb deep;

  const TileOption(this.key, this.label, this.hint, this.normal, this.deep);

  /// 打包成 0xRRGGBB，测试里直接跟出图角落的像素比。
  int get normalValue => normal.value;
  int get deepValue => deep.value;

  /// 米灰是默认值：比纯白耐看，也不会像灰底那样显脏。
  static const warm = TileOption(
    'warm',
    '米灰',
    '默认。比纯白耐看，深色浅色都不打架。',
    Rgb(0xF2, 0xF2, 0xF0),
    Rgb(0xDC, 0xDC, 0xD8),
  );

  static const white = TileOption(
    'white',
    '纯白',
    '最干净，浅色衣服会换深一档垫底。',
    Rgb(0xFF, 0xFF, 0xFF),
    Rgb(0xEC, 0xEC, 0xEA),
  );

  static const grey = TileOption(
    'grey',
    '浅灰',
    '偏冷，白色和米色的衣服最跳。',
    Rgb(0xE6, 0xE6, 0xE4),
    Rgb(0xC9, 0xC9, 0xC6),
  );

  static const beige = TileOption(
    'beige',
    '暖米',
    '偏暖，适合绝大多数日常衣柜。',
    Rgb(0xF0, 0xEB, 0xE0),
    Rgb(0xD9, 0xD0, 0xC0),
  );

  static const all = <TileOption>[warm, white, grey, beige];

  static const defaultKey = 'warm';

  static TileOption of(String? key) => all.firstWhere(
        (e) => e.key == key,
        orElse: () => warm,
      );
}

/// 默认底色，保留旧名字给测试与文档引用。
const kTileColorValue = 0xFFF2F2F0;

/// 处理结果。
class ProcessedResult {
  /// 统一排版后的正方形 JPEG（长边 ≤ [kMaxEdge]）。
  final Uint8List processed;
  final Uint8List thumb;

  /// 主色，`#RRGGBB`；无法提取时为 null。
  final String? colorHex;
  final String? colorName;

  /// mask 面积占比。< 5% 或 > 95% 判为抠图失败，见 §5.2。
  final double maskRatio;

  /// 是否真的抠过图。false 表示没有分割模型、只做了排版。
  final bool segmented;

  const ProcessedResult({
    required this.processed,
    required this.thumb,
    this.colorHex,
    this.colorName,
    this.maskRatio = 1.0,
    this.segmented = false,
  });

  bool get maskFailed => maskRatio < 0.05 || maskRatio > 0.95;
}

const kMaxEdge = 1600;
const kThumbEdge = 300;
const jpegQuality = 85;

/// 前景最大边 × 该系数 = 画布边长，即四周约 12% 留白。
const kCanvasScale = 1.25;

/// 主流程。在 Isolate 里跑，主线程只更新进度。
///
/// [tileKey] 是底色方案 key（见 [TileOption]），传 null 用默认米灰。
ProcessedResult processBytes(
  Uint8List input,
  ByteData? mask, {
  int maxEdge = kMaxEdge,
  String? tileKey,
}) {
  // decodeImage 对某些坏字节抛的是 RangeError/ArgumentError 而不是返回 null，
  // 统一收成 FormatException：调用方只需要处理一种失败形态。
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('无法解码图片');
  }

  // EXIF 方向必须先修正，否则统一排版会因相机方向而歪。
  final base = img.bakeOrientation(decoded);

  final useMask = mask != null;
  final double ratio = useMask ? _maskRatio(mask) : 1.0;
  final maskSide = useMask ? _maskSide(mask) : 0;

  final canvas = _findForeground(base, mask, maskSide);

  final tile = _pickTileColor(base, canvas, TileOption.of(tileKey));
  final square = _composeSquare(base, canvas, tile, mask, maskSide);

  final scaled = _resizeMax(square, maxEdge);

  final ColorSample? sample = useMask
      ? _extractColor(base, canvas, mask, maskSide)
      : _extractColorNoMask(base);

  return ProcessedResult(
    processed: img.encodeJpg(scaled, quality: jpegQuality),
    thumb: img.encodeJpg(
      _resizeMax(square, kThumbEdge),
      quality: jpegQuality,
    ),
    colorHex: sample?.hex,
    colorName: sample?.name,
    maskRatio: ratio,
    segmented: useMask,
  );
}

double _maskRatio(ByteData mask) {
  final total = mask.lengthInBytes;
  if (total == 0) return 0;
  var on = 0;
  for (var i = 0; i < total; i++) {
    if (mask.getUint8(i) > 127) on++;
  }
  return on / total;
}

class _Box {
  final int x, y, w, h;
  const _Box(this.x, this.y, this.w, this.h);
}

/// mask 的包围盒；没有 mask 时用整张图。
_Box _findForeground(img.Image im, ByteData? mask, int maskSide) {
  if (mask == null) {
    return _Box(0, 0, im.width, im.height);
  }
  final mw = maskSide;
  final mh = maskSide;
  var minX = mw, minY = mh, maxX = -1, maxY = -1;

  for (var y = 0; y < mh; y++) {
    for (var x = 0; x < mw; x++) {
      if (mask.getUint8(y * mw + x) > 127) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return _Box(0, 0, im.width, im.height);

  // mask 分辨率可能低于原图，按比例放大回原图坐标。
  final sx = im.width / mw;
  final sy = im.height / mh;
  return _Box(
    (minX * sx).floor(),
    (minY * sy).floor(),
    math.max(1, ((maxX - minX + 1) * sx).ceil()),
    math.max(1, ((maxY - minY + 1) * sy).ceil()),
  );
}

/// 约定：mask 是灰度正方形，边长 = sqrt(字节数)。
int _maskSide(ByteData mask) => math.sqrt(mask.lengthInBytes).round();

/// 前景平均亮度 > 0.85 时换深一档底色，否则浅色衣物会和背景融掉。
///
/// 阈值按底色自身亮度区分：纯白底亮，浅色衣物和它的差值天然小，
/// 所以阈值要压低一点，否则白 T 恤贴白底还是看不出来。
Rgb _pickTileColor(img.Image im, _Box box, TileOption option) {
  var sum = 0.0;
  var n = 0;
  final stepX = math.max(1, box.w ~/ 24);
  final stepY = math.max(1, box.h ~/ 24);
  for (var y = box.y; y < box.y + box.h; y += stepY) {
    for (var x = box.x; x < box.x + box.w; x += stepX) {
      if (x < 0 || y < 0 || x >= im.width || y >= im.height) continue;
      final p = im.getPixel(x, y);
      sum += _luminance(p.r, p.g, p.b);
      n++;
    }
  }
  final avg = n == 0 ? 0.0 : sum / n;
  final baseLum = _luminance(option.normal.r, option.normal.g, option.normal.b);
  // 底色越亮，允许的「前景和底色差」越小，阈值相应下调。
  final threshold = baseLum > 0.97 ? 0.80 : 0.85;
  return avg > threshold ? option.deep : option.normal;
}

double _luminance(num r, num g, num b) =>
    (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;

/// 按 §5.5 合成正方形：边长 = 前景最大边 × 1.25，前景几何居中。
img.Image _composeSquare(
  img.Image src,
  _Box box,
  Rgb tile,
  ByteData? mask,
  int maskSide,
) {
  final fgMax = math.max(box.w, box.h);
  final side = math.max(1, (fgMax * kCanvasScale).round());

  final out = img.Image(width: side, height: side, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(tile.r, tile.g, tile.b));

  // 前景在画布中的左上角：几何居中，不按视觉重心。
  final dx = (side - box.w) / 2.0;
  final dy = (side - box.h) / 2.0;

  if (mask == null) {
    // 没有分割模型时，整块矩形贴上去，四边留白仍然成立。
    for (var y = 0; y < box.h; y++) {
      final sy = box.y + y;
      if (sy < 0 || sy >= src.height) continue;
      for (var x = 0; x < box.w; x++) {
        final sx = box.x + x;
        if (sx < 0 || sx >= src.width) continue;
        final p = src.getPixel(sx, sy);
        final ox = (dx + x).round();
        final oy = (dy + y).round();
        if (ox < 0 || oy < 0 || ox >= side || oy >= side) continue;
        out.setPixelRgb(ox, oy, p.r, p.g, p.b);
      }
    }
    return out;
  }

  final mw = maskSide;
  final mh = maskSide;

  for (var y = 0; y < box.h; y++) {
    final sy = box.y + y;
    if (sy < 0 || sy >= src.height) continue;
    for (var x = 0; x < box.w; x++) {
      final sx = box.x + x;
      if (sx < 0 || sx >= src.width) continue;

      final mx = (sx * mw / src.width).floor().clamp(0, mw - 1);
      final my = (sy * mh / src.height).floor().clamp(0, mh - 1);
      final a = mask.getUint8(my * mw + mx);
      if (a < 8) continue;

      final p = src.getPixel(sx, sy);
      final alpha = a / 255.0;
      final ox = (dx + x).round();
      final oy = (dy + y).round();
      if (ox < 0 || oy < 0 || ox >= side || oy >= side) continue;

      out.setPixelRgb(
        ox,
        oy,
        (p.r * alpha + tile.r * (1 - alpha)).round(),
        (p.g * alpha + tile.g * (1 - alpha)).round(),
        (p.b * alpha + tile.b * (1 - alpha)).round(),
      );
    }
  }
  return out;
}

img.Image _resizeMax(img.Image im, int maxEdge) {
  if (im.width <= maxEdge && im.height <= maxEdge) return im;
  return im.width >= im.height
      ? img.copyResize(im,
          width: maxEdge, interpolation: img.Interpolation.average)
      : img.copyResize(im,
          height: maxEdge, interpolation: img.Interpolation.average);
}

class ColorSample {
  final String hex;
  final String name;
  const ColorSample(this.hex, this.name);
}

/// 预设 20 色表，只用于展示和筛选，不参与分类（见 §5.4）。
const _colorTable = <(String, int, int, int)>[
  ('黑', 0x1A, 0x1A, 0x1A),
  ('炭灰', 0x3A, 0x3A, 0x3A),
  ('中灰', 0x8A, 0x8A, 0x8A),
  ('浅灰', 0xC6, 0xC6, 0xC4),
  ('米白', 0xEF, 0xEA, 0xDF),
  ('白', 0xFA, 0xFA, 0xF7),
  ('奶油', 0xF2, 0xE2, 0xC4),
  ('驼', 0xC0, 0x9A, 0x6B),
  ('棕', 0x7A, 0x56, 0x3C),
  ('咖啡', 0x4E, 0x38, 0x2A),
  ('酒红', 0x6E, 0x27, 0x30),
  ('红', 0xC0, 0x39, 0x3A),
  ('橘', 0xD9, 0x7A, 0x3C),
  ('黄', 0xE0, 0xC0, 0x4A),
  ('橄榄绿', 0x6E, 0x74, 0x3C),
  ('绿', 0x3F, 0x7A, 0x4B),
  ('墨绿', 0x22, 0x4A, 0x38),
  ('藏青', 0x24, 0x33, 0x52),
  ('蓝', 0x3A, 0x6E, 0xB0),
  ('紫', 0x6A, 0x4B, 0x82),
];

ColorSample? _sampleToResult(int r, int g, int b) {
  var bestName = _colorTable.first.$1;
  var bestDist = double.infinity;
  for (final c in _colorTable) {
    final d =
        math.pow(c.$2 - r, 2) + math.pow(c.$3 - g, 2) + math.pow(c.$4 - b, 2);
    if (d < bestDist) {
      bestDist = d.toDouble();
      bestName = c.$1;
    }
  }
  final hex = '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
  return ColorSample(hex, bestName);
}

/// 有 mask：只在前景像素上做 k-means(k=3)，取占比最大且亮度适中的簇。
ColorSample? _extractColor(
    img.Image im, _Box box, ByteData mask, int maskSide) {
  final mw = maskSide;
  final mh = maskSide;

  final pixels = <(int, int, int)>[];
  final stepX = math.max(1, box.w ~/ 64);
  final stepY = math.max(1, box.h ~/ 64);

  for (var y = box.y; y < box.y + box.h; y += stepY) {
    if (y < 0 || y >= im.height) continue;
    for (var x = box.x; x < box.x + box.w; x += stepX) {
      if (x < 0 || x >= im.width) continue;
      final mx = (x * mw / im.width).floor().clamp(0, mw - 1);
      final my = (y * mh / im.height).floor().clamp(0, mh - 1);
      if (mask.getUint8(my * mw + mx) < 128) continue;
      final p = im.getPixel(x, y);
      pixels.add((p.r.toInt(), p.g.toInt(), p.b.toInt()));
    }
  }
  return _kmeansDominant(pixels);
}

/// 无 mask：整张图降采样后聚类，会被背景色污染，因此只作为降级方案。
ColorSample? _extractColorNoMask(img.Image im) {
  final pixels = <(int, int, int)>[];
  final stepX = math.max(1, im.width ~/ 64);
  final stepY = math.max(1, im.height ~/ 64);
  for (var y = 0; y < im.height; y += stepY) {
    for (var x = 0; x < im.width; x += stepX) {
      final p = im.getPixel(x, y);
      pixels.add((p.r.toInt(), p.g.toInt(), p.b.toInt()));
    }
  }
  return _kmeansDominant(pixels);
}

ColorSample? _kmeansDominant(List<(int, int, int)> pixels) {
  if (pixels.isEmpty) return null;

  // k-means 初值取分位数，避免随机性（结果需要可复现）。
  pixels.sort((a, b) => _lum(a).compareTo(_lum(b)));
  final k = 3;
  var centers = <List<double>>[
    for (var i = 0; i < k; i++)
      _toDouble(pixels[
          ((i + 0.5) / k * pixels.length).floor().clamp(0, pixels.length - 1)]),
  ];

  var assign = List<int>.filled(pixels.length, 0);
  for (var iter = 0; iter < 8; iter++) {
    for (var i = 0; i < pixels.length; i++) {
      var best = 0;
      var bestD = double.infinity;
      for (var c = 0; c < k; c++) {
        final d = _dist2(pixels[i], centers[c]);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      assign[i] = best;
    }
    final sums = List.generate(k, (_) => <double>[0, 0, 0]);
    final counts = List<int>.filled(k, 0);
    for (var i = 0; i < pixels.length; i++) {
      final c = assign[i];
      sums[c][0] += pixels[i].$1;
      sums[c][1] += pixels[i].$2;
      sums[c][2] += pixels[i].$3;
      counts[c]++;
    }
    for (var c = 0; c < k; c++) {
      if (counts[c] == 0) continue;
      centers[c] = [
        sums[c][0] / counts[c],
        sums[c][1] / counts[c],
        sums[c][2] / counts[c],
      ];
    }
  }

  final counts = List<int>.filled(k, 0);
  for (final a in assign) {
    counts[a]++;
  }

  // 取占比最大、且亮度不过白也不过黑的簇（过滤阴影与高光）。
  var bestIdx = -1;
  var bestCount = -1;
  for (var c = 0; c < k; c++) {
    final lum = (0.2126 * centers[c][0] +
            0.7152 * centers[c][1] +
            0.0722 * centers[c][2]) /
        255.0;
    if (lum < 0.06 || lum > 0.97) continue;
    if (counts[c] > bestCount) {
      bestCount = counts[c];
      bestIdx = c;
    }
  }
  if (bestIdx < 0) {
    // 全被过滤掉时退回最大的簇，总比没有颜色好。
    bestIdx = counts.indexOf(counts.reduce(math.max));
  }

  return _sampleToResult(
    centers[bestIdx][0].round(),
    centers[bestIdx][1].round(),
    centers[bestIdx][2].round(),
  );
}

double _lum((int, int, int) p) => 0.2126 * p.$1 + 0.7152 * p.$2 + 0.0722 * p.$3;

double _dist2((int, int, int) p, List<double> c) => (math.pow(p.$1 - c[0], 2) +
        math.pow(p.$2 - c[1], 2) +
        math.pow(p.$3 - c[2], 2))
    .toDouble();

List<double> _toDouble((int, int, int) p) =>
    [p.$1.toDouble(), p.$2.toDouble(), p.$3.toDouble()];

/// 在 Isolate 里跑处理，主线程只拿结果。
/// 单次批量超过 20 张时应排队处理并显示进度（见 §7 性能约束）。
Future<ProcessedResult> processInIsolate(
  Uint8List input, {
  ByteData? mask,
  int maxEdge = kMaxEdge,
  String? tileKey,
}) {
  return Isolate.run(
      () => processBytes(input, mask, maxEdge: maxEdge, tileKey: tileKey));
}
