import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingtian_chuanshenme/core/vision.dart';
import 'package:mingtian_chuanshenme/data/db.dart';
import 'package:mingtian_chuanshenme/models.dart';

/// 校验打包进 App 的真实资产，而不是手写的假数据。
///
/// 这里能挡住的是一类很隐蔽的错：`labels.json` 里二级类别的**顺序**
/// 决定了自动分类写进库里的 `b_<l1>_<index>`，一旦两边顺序不一致，
/// App 不会报错，只会把卫衣存成「短袖T恤」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Labels labels;

  setUpAll(() async {
    final source = await rootBundle.loadString('assets/models/labels.json');
    labels = Labels.fromJson(source);
  });

  test('labels.json 能解析，且覆盖全部七个一级类别', () {
    expect(labels.l1Keys.toSet(), L1Category.all.map((c) => c.code).toSet());
    for (final c in L1Category.all) {
      expect(labels.l1Label[c.code], c.label, reason: '${c.code} 的中文名应与内置类别一致');
    }
  });

  test('每个一级类别下的二级类别与内置类别逐个对齐', () {
    for (final c in L1Category.all) {
      final builtin = kBuiltinCategories[c.code]!;
      final fromAssets = labels.l2[c.code] ?? const <L2Item>[];
      expect(fromAssets.map((e) => e.name).toList(), builtin,
          reason: '${c.label} 的二级类别顺序必须与 db.dart 完全一致，'
              '否则 b_${c.code}_<index> 会指向错的类别');
    }
  });

  test('每个向量维度一致且已归一化', () {
    final dims = <int>{};
    for (final v in labels.l1Vector.values) {
      dims.add(v.length);
      final norm = l2Normalize(v);
      var sum = 0.0;
      for (final x in norm) {
        sum += x * x;
      }
      expect(sum, closeTo(1.0, 1e-3), reason: '一级向量应当已归一化');
    }
    for (final list in labels.l2.values) {
      for (final item in list) {
        dims.add(item.vector.length);
      }
    }
    expect(dims, hasLength(1), reason: '所有向量维度必须相同，才能直接点积');
  });

  test('标签文件里的 version 是 1', () async {
    final raw = await rootBundle.loadString('assets/models/labels.json');
    final root = jsonDecode(raw) as Map<String, dynamic>;
    expect(root['version'], 1);
    expect(root['dim'], labels.l1Vector.values.first.length);
  });
}
