import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mingtian_chuanshenme/core/image_processor.dart';
import 'package:mingtian_chuanshenme/models.dart';

/// 这些是纯函数、无 IO，最容易静默出错又最容易被忽略：
/// 底色选错不会报错，只会让相册看起来不整齐。
void main() {
  group('TileOption', () {
    test('默认是米灰', () {
      expect(TileOption.of(null).key, 'warm');
    });

    test('认不出来的 key 退回默认，不抛错', () {
      expect(TileOption.of('nope').key, 'warm');
    });

    test('每一档的深色都比浅色暗', () {
      for (final o in TileOption.all) {
        expect(_lum(o.deep), lessThan(_lum(o.normal)),
            reason: '${o.label} 的深色不深');
      }
    });

    test('key 不重复', () {
      final keys = TileOption.all.map((e) => e.key).toSet();
      expect(keys.length, TileOption.all.length);
    });
  });

  group('SortMode', () {
    test('默认最近加的', () {
      expect(SortMode.of(null), SortMode.newest);
      expect(SortMode.of('bogus'), SortMode.newest);
    });

    test('按类别的顺序跟上装→下装→…的界面顺序一致', () {
      // 关键点：不能是字典序。字典序里「下装」(bottom) 会排到「上装」(top) 前面。
      final byCategory = SortMode.category.orderBy;
      final topAt = byCategory.indexOf("WHEN 'top'");
      final bottomAt = byCategory.indexOf("WHEN 'bottom'");
      expect(topAt, greaterThanOrEqualTo(0));
      expect(topAt, lessThan(bottomAt));
    });

    test('只有按类别带 CASE 表达式', () {
      for (final m in SortMode.values) {
        // 注意不能直接找 'CASE'：按名称那条里有 'NOCASE'，会误判。
        expect(
            m.orderBy.trimLeft().startsWith('CASE ') ||
                m.orderBy.contains(' CASE '),
            m == SortMode.category,
            reason: '${m.label} 的 orderBy：${m.orderBy}');
      }
    });
  });

  group('processBytes 的底色', () {
    // 有 mask 时才会只看前景；没有 mask 时整块矩形都算前景，底色判断会被
    // 桌面背景带偏 —— 这是设计文档里写明的已知限制，所以这里都带 mask 测。
    test('深色衣物用浅底色', () {
      final r = processBytes(_garmentOnWhite(40, 40, 40), _squareMask(),
          maxEdge: 300);
      expectCorner(r.processed, TileOption.warm.normalValue);
    });

    test('浅色衣物自动换深一档底色', () {
      final r = processBytes(_garmentOnWhite(250, 250, 248), _squareMask(),
          maxEdge: 300);
      expectCorner(r.processed, TileOption.warm.deepValue);
    });

    test('换一档底色，出图跟着变', () {
      final warm = processBytes(_garmentOnWhite(40, 40, 40), _squareMask(),
          maxEdge: 300, tileKey: 'warm');
      final grey = processBytes(_garmentOnWhite(40, 40, 40), _squareMask(),
          maxEdge: 300, tileKey: 'grey');
      expectCorner(warm.processed, TileOption.warm.normalValue);
      expectCorner(grey.processed, TileOption.grey.normalValue);
    });

    test('纯白底上，浅色衣物也会被换成深一档', () {
      // 纯白底亮，阈值要更低；否则白 T 恤贴白底完全看不出轮廓。
      final r = processBytes(_garmentOnWhite(250, 250, 248), _squareMask(),
          maxEdge: 300, tileKey: 'white');
      expectCorner(r.processed, TileOption.white.deepValue);
    });

    test('正方形、长边不超过 maxEdge', () {
      final r = processBytes(_garmentOnWhite(40, 40, 40), _squareMask(),
          maxEdge: 300);
      final im = img.decodeJpg(r.processed)!;
      expect(im.width, im.height);
      expect(im.width, lessThanOrEqualTo(300));
    });

    test('解不出来的字节抛 FormatException 而不是崩在别处', () {
      expect(
        () => processBytes(Uint8List.fromList([1, 2, 3]), null),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

double _lum(Rgb c) => (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255.0;

/// 测试图边长。mask 约定是灰度正方形，边长 = sqrt(字节数)。
const _side = 200;

/// 方框区域（前景）。
const _boxFrom = 60;
const _boxTo = 140;

/// 造一张「方框形状的衣物铺在白桌面上」的图。
Uint8List _garmentOnWhite(int r, int g, int b) {
  final im = img.Image(width: _side, height: _side);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(im,
      x1: _boxFrom,
      y1: _boxFrom,
      x2: _boxTo,
      y2: _boxTo,
      color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(im));
}

/// 正方形 alpha mask，只有中间那块是前景。
ByteData _squareMask() {
  final m = Uint8List(_side * _side);
  for (var y = _boxFrom; y <= _boxTo; y++) {
    for (var x = _boxFrom; x <= _boxTo; x++) {
      m[y * _side + x] = 255;
    }
  }
  return ByteData.sublistView(m);
}

/// 读左上角底色，容 JPEG 压缩误差（每个通道 ±6）。
void expectCorner(Uint8List jpg, int expected) {
  final p = img.decodeJpg(jpg)!.getPixel(1, 1);
  final got = <int>[p.r.toInt(), p.g.toInt(), p.b.toInt()];
  final want = <int>[
    (expected >> 16) & 0xFF,
    (expected >> 8) & 0xFF,
    expected & 0xFF
  ];
  for (var i = 0; i < 3; i++) {
    expect((got[i] - want[i]).abs(), lessThanOrEqualTo(6),
        reason: '第 $i 通道：实得 $got，期望 $want');
  }
}
