import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mingtian_chuanshenme/core/image_processor.dart';
import 'package:mingtian_chuanshenme/core/vision.dart';
import 'package:mingtian_chuanshenme/models.dart';

/// 在真机 / 模拟器上验 ONNX 管线。
///
/// 为什么非要有这个：golden 测试跑在电脑的 Flutter 引擎里，`flutter_onnxruntime`
/// 的 platform channel 根本不存在，跑出来的 `VisionResult` 全是 null —— 看着是
/// 绿的，实际上一个字也没验到。这个文件必须在设备上跑：
///
///   flutter test integration_test/vision_device_test.dart -d <device>
///
/// 电脑上的 `vision_test.dart` 只验纯函数，不碰模型。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 每张图期望的一级类别。这些是真实衣物照，用 Python 那边验过的同一批。
  const expectations = {
    'tshirt_0.jpg': ['top'],
    'sneaker_0.jpg': ['shoe'],
    'dress_1.jpg': ['dress'],
    'hat_0.jpg': ['acc'],
    'backpack_0.jpg': ['bag'],
    'jacket_0.jpg': ['outer'],
  };

  late ClosetVision vision;

  setUpAll(() async {
    vision = await ClosetVision.load();
  });

  tearDownAll(() async {
    await vision.dispose();
  });

  testWidgets('模型能从 asset 加载，标签也读得出来', (tester) async {
    expect(vision.labels.l1Keys.toSet(),
        L1Category.all.map((c) => c.code).toSet());
    expect(vision.labels.l2['top'], isNotEmpty);
  });

  testWidgets('六张真实衣物照，一级类别全中', (tester) async {
    final misses = <String>[];
    final lines = <String>[];

    for (final entry in expectations.entries) {
      final data = await rootBundle.load('integration_test/samples/${entry.key}');
      final bytes = data.buffer.asUint8List();

      final sw = Stopwatch()..start();
      final result = await vision.analyze(bytes);
      sw.stop();

      final cls = result.cls;
      expect(cls, isNotNull, reason: '${entry.key} 分类整条挂了');
      final got = cls!.top1.key;
      final ok = entry.value.contains(got);
      lines.add('${entry.key} -> $got '
          '(${(cls.confidence * 100).toStringAsFixed(0)}%) '
          '${result.mask == null ? "用原图" : "抠图 ${(result.maskRatio * 100).toStringAsFixed(0)}%"} '
          '${sw.elapsedMilliseconds}ms ${ok ? "OK" : "MISS"}');
      if (!ok) misses.add('${entry.key} 期望 ${entry.value} 实得 $got');
    }

    // 把每张的结果打出来 —— 万一挂了，日志里能直接看到是哪种错法。
    debugPrint('--- 真机分类结果 ---');
    for (final l in lines) {
      debugPrint(l);
    }

    // 允许错 1/6：Python 那边 fp16 是 14/16，掉两张里有一张的样本本身就是
    // 皮革横截面（不是衣服）。要求全中会让这个测试变成噪音。
    expect(misses.length, lessThanOrEqualTo(1),
        reason: '错太多，模型多半没真正跑起来：\n${misses.join("\n")}');
  });

  testWidgets('抠图出来的 mask 是正方形，前景面积在合理区间', (tester) async {
    final data = await rootBundle.load('integration_test/samples/tshirt_0.jpg');
    final result = await vision.analyze(data.buffer.asUint8List());

    // tshirt_0 是白底上的深色 T 恤，抠图应当成功且面积不大。
    expect(result.mask, isNotNull, reason: '这件不该抠失败');
    final side = (result.maskRatio > 0) ? result.mask!.lengthInBytes : 0;
    expect(side, kSegSide * kSegSide, reason: 'mask 应该是 320×320 的字节');
    expect(maskUsable(result.maskRatio), isTrue);
  });

  testWidgets('端到端：抠图 + 分类 + 统一排版一次跑完', (tester) async {
    final data = await rootBundle.load('integration_test/samples/tshirt_0.jpg');
    final bytes = data.buffer.asUint8List();

    final seen = await vision.analyze(bytes);
    final processed = await processInIsolate(
      bytes,
      mask: seen.mask,
      tileKey: TileOption.defaultKey,
    );

    // 正方形、长边受限、底色是选的米灰（左上角是留白，不带前景）。
    expect(processed.processed, isNotEmpty);
    expect(processed.colorName, isNotNull);

    final kind = seen.cls!.l2?.name;
    final name = autoName(colorName: processed.colorName, kind: kind);
    debugPrint('自动起名结果：$name');
    expect(name, isNot('新衣服'), reason: '颜色和类别都识别出来了，名字不该退到兜底');
  });
}
