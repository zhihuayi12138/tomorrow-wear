import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mingtian_chuanshenme/core/vision.dart';

/// 这些是 [vision.dart] 里不带 ORT 的纯函数。
///
/// 为什么值得单独测：分类错一件衣服用户只是改一下下拉框，
/// 但这些函数的错法是**静默**的 —— 阈值差一点，低置信提示就再也不出现；
/// 归一化漏一步，所有类别的概率会一起变成 0.14，看起来「很正常」。
void main() {
  group('l2Normalize', () {
    test('长度归一化为 1', () {
      final v = l2Normalize([3, 4]);
      expect(v[0], closeTo(0.6, 1e-9));
      expect(v[1], closeTo(0.8, 1e-9));
    });

    test('零向量原样返回，不产生 NaN', () {
      final v = l2Normalize([0, 0, 0]);
      expect(v, [0, 0, 0]);
      expect(v.any((x) => x.isNaN), isFalse);
    });

    test('不改原列表', () {
      final src = [3.0, 4.0];
      l2Normalize(src);
      expect(src, [3.0, 4.0]);
    });
  });

  group('cosineScores', () {
    test('归一化后同向为 1，反向为 -1，正交为 0', () {
      final probe = l2Normalize([1.0, 0.0]);
      final scores = cosineScores([
        l2Normalize([2.0, 0.0]),
        l2Normalize([-1.0, 0.0]),
        l2Normalize([0.0, 5.0]),
      ], probe);
      expect(scores[0], closeTo(1.0, 1e-9));
      expect(scores[1], closeTo(-1.0, 1e-9));
      expect(scores[2], closeTo(0.0, 1e-9));
    });

    test('长度不等的向量不越界', () {
      final scores = cosineScores([
        [1.0, 1.0, 1.0],
      ], [
        1.0
      ]);
      expect(scores, hasLength(1));
      expect(scores.first.isFinite, isTrue);
    });
  });

  group('topProbability', () {
    test('两类打平时是 0.5', () {
      expect(topProbability([0.1, 0.1]), closeTo(0.5, 1e-9));
    });

    test('领先越多概率越高，但不会超过 1', () {
      final weak = topProbability([0.20, 0.18]);
      final strong = topProbability([0.25, 0.05]);
      expect(weak, lessThan(strong));
      expect(strong, lessThanOrEqualTo(1.0));
    });

    test('空列表返回 0，不抛错', () {
      expect(topProbability([]), 0);
    });

    // 这条锁的是实验里定过来的那个数字：不乘温度时余弦只有 0.05~0.25，
    // softmax 出来一片 0.14~0.16，0.45 的阈值永远碰不到。
    test('温度 100 时，余弦差 0.02 也足以拉开概率', () {
      final p = topProbability([0.22, 0.20]);
      expect(p, greaterThan(0.6));
    });
  });

  group('argMax', () {
    test('取最大值的下标', () {
      expect(argMax([0.1, 0.9, 0.3]), 1);
    });

    test('并列取第一个', () {
      expect(argMax([0.5, 0.5]), 0);
    });

    test('空列表返回 0', () {
      expect(argMax([]), 0);
    });
  });

  group('maskFromLogits', () {
    test('按 min-max 归一化后二值化，只输出 0 或 255', () {
      final mask = maskFromLogits(Float32List.fromList([-7, -3, 0, 2, 9]));
      expect(mask.every((v) => v == 0 || v == 255), isTrue);
      // -7 是最小值映射到 0，9 是最大值映射到 1。
      expect(mask.first, 0);
      expect(mask.last, 255);
    });

    test('全平的输出当成没有前景', () {
      final mask = maskFromLogits(Float32List.fromList([3, 3, 3]));
      expect(mask.every((v) => v == 0), isTrue);
    });

    test('空输入返回空', () {
      expect(maskFromLogits(Float32List(0)), isEmpty);
    });
  });

  group('maskUsable', () {
    test('面积太小或太大都判不可信', () {
      expect(maskUsable(0.01), isFalse);
      expect(maskUsable(0.049), isFalse);
      expect(maskUsable(0.96), isFalse);
      expect(maskUsable(0.99), isFalse);
    });

    test('正常面积可用，边界值算可用', () {
      expect(maskUsable(0.3), isTrue);
      expect(maskUsable(0.051), isTrue);
      // 边界本身取「可用」：判据是「小于 5%」和「大于 95%」，
      // 正好 5% 不在其中。
      expect(maskUsable(kMaskMinRatio), isTrue);
      expect(maskUsable(kMaskMaxRatio), isTrue);
    });
  });

  group('autoName', () {
    test('颜色 + 类别拼在一起', () {
      expect(autoName(colorName: '灰', kind: '卫衣'), '灰卫衣');
    });

    test('只有类别就用类别', () {
      expect(autoName(kind: '卫衣'), '卫衣');
    });

    test('只有颜色就说这是件什么颜色的衣服', () {
      expect(autoName(colorName: '灰'), '灰的衣服');
    });

    test('两样都没有退回兜底名', () {
      expect(autoName(), '新衣服');
      expect(autoName(fallback: '待确认'), '待确认');
    });

    test('空白字符串不算有值', () {
      expect(autoName(colorName: '  ', kind: ''), '新衣服');
    });
  });

  group('Labels.fromJson', () {
    const json = '''
{
  "version": 1,
  "dim": 2,
  "l1": {
    "top": {"label": "上装", "vector": [1.0, 0.0]},
    "shoe": {"label": "鞋", "vector": [0.0, 1.0]}
  },
  "l2": {
    "top": [{"name": "卫衣", "vector": [1.0, 0.0]}]
  }
}
''';

    test('读出中文名与向量', () {
      final labels = Labels.fromJson(json);
      expect(labels.l1Label['top'], '上装');
      expect(labels.l1Vector['top'], [1.0, 0.0]);
      expect(labels.l2['top']!.single.name, '卫衣');
      expect(labels.l1Keys, hasLength(2));
    });

    test('向量当成分类器的探针能算出正确的类别', () {
      final labels = Labels.fromJson(json);
      final probe = l2Normalize([0.9, 0.1]);
      final keys = labels.l1Keys;
      final scores = cosineScores(
        [for (final k in keys) labels.l1Vector[k]!],
        probe,
      );
      expect(keys[argMax(scores)], 'top');
    });
  });
}
