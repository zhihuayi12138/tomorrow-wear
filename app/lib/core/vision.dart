import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// 抠图模型（u2netp）的输入边长。
const kSegSide = 320;

/// 分类模型（mobileclip_s0 图像编码器）的输入边长。
const kVisionSide = 256;

/// mask 二值化阈值：模型输出经 min-max 归一化到 0..1 之后取这个值判前景。
const kMaskOn = 0.5;

/// softmax 温度。余弦相似度本身在 0.05~0.25 这个很窄的区间里，
/// 直接用会得到一堆 0.15 左右的概率、没法设阈值，乘 100 才拉开。
/// 这个数是拿 16 张真实衣物照试出来的：判对时最低 0.54、判错时 0.41 和 0.56，
/// 所以 0.45 的提示阈值刚好落在中间。
const kConfidenceTemperature = 100.0;

/// 抠图 mask 面积占比低于这个数，说明模型基本没找到衣服（多半是没平铺好、
/// 或者衣服和背景同色），此时**必须退回整块矩形**。
/// 实测过：不做这个兜底，分类准确率会从 88% 掉到 75%，
/// 因为失败的 mask 把衣服裁掉了。
const kMaskMinRatio = 0.05;
const kMaskMaxRatio = 0.95;

/// 一个一级类别的打分。
class L1Score {
  final String key;
  final String label;
  final double p;
  const L1Score(this.key, this.label, this.p);
}

/// 一个二级类别的打分。
class L2Score {
  final String name;
  final double p;

  /// 在 `kBuiltinCategories[l1]` 里的下标。labels.json 的条目顺序与
  /// `app/lib/data/db.dart` 的 `kBuiltinCategories` 逐项对应，
  /// 所以这个下标可以直接拼出内置类别 id `b_<l1>_<index>`。
  /// 用下标而不是按名字查库，是因为内置类别允许改名 —— 改名之后按名字就找不到了。
  final int index;

  const L2Score(this.name, this.p, this.index);
}

/// 一次自动分类的结果。
class Classification {
  final L1Score top1;
  final L1Score top2;

  /// 选中的二级类别；该一级下没有可比对的条目时为 null。
  final L2Score? l2;

  const Classification({
    required this.top1,
    required this.top2,
    this.l2,
  });

  double get confidence => top1.p;

  /// 置信度够不够写进库里当「已定」。
  bool get confident => top1.p >= kConfidenceThreshold;
}

/// 低于这个概率就在待确认队列里高亮「类别拿不准」。
const kConfidenceThreshold = 0.45;

/// 一次视觉分析的结果：mask 与分类一次解码、两次推理。
class VisionResult {
  /// 方形灰度 mask，边长 [kSegSide]，>127 为前景。
  /// **为 null 表示抠图不可信**（面积 <5% / >95% / 模型没加载），
  /// 调用方应当退回整块矩形。
  final ByteData? mask;

  /// 抠图失败时的原始面积占比，用于日志与以后的诊断界面。
  final double maskRatio;

  final Classification? cls;

  const VisionResult({this.mask, this.maskRatio = 0, this.cls});
}

/// 离线标签：[类别 key] → 512 维已归一化向量。
class Labels {
  final Map<String, String> l1Label;
  final Map<String, List<double>> l1Vector;
  final Map<String, List<L2Item>> l2;

  const Labels({
    required this.l1Label,
    required this.l1Vector,
    required this.l2,
  });

  List<String> get l1Keys => l1Vector.keys.toList(growable: false);

  static Labels fromJson(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final l1 = <String, String>{};
    final vec = <String, List<double>>{};
    for (final e in (root['l1'] as Map<String, dynamic>).entries) {
      final m = e.value as Map<String, dynamic>;
      l1[e.key] = m['label'] as String;
      vec[e.key] =
          (m['vector'] as List).map((v) => (v as num).toDouble()).toList();
    }
    final l2 = <String, List<L2Item>>{};
    for (final e in (root['l2'] as Map<String, dynamic>).entries) {
      l2[e.key] = (e.value as List)
          .map((v) => L2Item(
                name: (v as Map<String, dynamic>)['name'] as String,
                vector: (v['vector'] as List)
                    .map((x) => (x as num).toDouble())
                    .toList(),
              ))
          .toList();
    }
    return Labels(l1Label: l1, l1Vector: vec, l2: l2);
  }
}

class L2Item {
  final String name;
  final List<double> vector;
  const L2Item({required this.name, required this.vector});
}

// ---------------------------------------------------------------------------
// 纯函数：都能在没有 ONNX Runtime 的环境里单测。
// ---------------------------------------------------------------------------

/// L2 归一化，返回新列表。零向量原样返回（避免除零）。
List<double> l2Normalize(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final n = math.sqrt(sum);
  if (n < 1e-9) return List<double>.from(v);
  return [for (final x in v) x / n];
}

/// [vectors] 每一行的余弦相似度（都已归一化，所以就是点积）。
List<double> cosineScores(List<List<double>> vectors, List<double> probe) {
  return [
    for (final row in vectors) _dot(row, probe),
  ];
}

double _dot(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  var s = 0.0;
  for (var i = 0; i < n; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// softmax 后的 top-1 概率。温度见 [kConfidenceTemperature]。
double topProbability(List<double> scores,
    {double temperature = kConfidenceTemperature}) {
  if (scores.isEmpty) return 0;
  final z = [for (final s in scores) s * temperature];
  final mx = z.reduce(math.max);
  var sum = 0.0;
  for (final v in z) {
    sum += math.exp(v - mx);
  }
  if (sum <= 0) return 0;
  // 减掉的 mx 就是最大值本身，所以分子的 exp(mx - mx) 恒为 1。
  return 1 / sum;
}

/// 最大值的下标。
int argMax(List<double> scores) {
  var best = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[best]) best = i;
  }
  return best;
}

/// 把模型输出的 logits 转成方形 mask 字节（>127 为前景）。
///
/// u2netp 的 `d0` 输出范围不固定（实测 -7 ~ +9 都有），必须逐张做 min-max
/// 归一化，再按 [kMaskOn] 二值化。
Uint8List maskFromLogits(Float32List logits) {
  final out = Uint8List(logits.length);
  if (logits.isEmpty) return out;
  var lo = logits[0], hi = logits[0];
  for (final v in logits) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  final span = hi - lo;
  if (span < 1e-6) return out; // 全平，当成没有前景
  for (var i = 0; i < logits.length; i++) {
    final t = (logits[i] - lo) / span;
    out[i] = t >= kMaskOn ? 255 : 0;
  }
  return out;
}

/// 前景占比。<5% 或 >95% 判为「抠图不可信」。
bool maskUsable(double ratio) =>
    ratio >= kMaskMinRatio && ratio <= kMaskMaxRatio;

/// 自动起名：颜色 + 二级类别，比如「灰色卫衣」。
///
/// 为什么是这两个而不是别的：录入时用户唯一一定会看的就是名字，
/// 而「灰色卫衣」这种名字比「待确认 3」好改一个数量级 —— 它已经对了七成，
/// 用户只需要把「灰」改成「浅灰」，而不是从头打。
/// 缺一样就退一级，两样都缺才用 [fallback]。
String autoName({
  String? colorName,
  String? kind,
  String fallback = '新衣服',
}) {
  final c = colorName?.trim() ?? '';
  final k = kind?.trim() ?? '';
  if (c.isNotEmpty && k.isNotEmpty) return '$c$k';
  if (k.isNotEmpty) return k;
  if (c.isNotEmpty) return '$c的衣服';
  return fallback;
}

// ---------------------------------------------------------------------------
// 模型
// ---------------------------------------------------------------------------

/// 手机上跑的两个模型：抠图（u2netp）+ 图像编码器（mobileclip_s0 fp16）。
///
/// 文本编码器**不在手机上**：类别提示词在打包时已离线算好存进
/// `assets/models/labels.json`，所以这里只做「图像 → 512 维向量 → 点积」。
/// 好处是包体少 40 MB，且新增二级类别只要在设备上把该类的向量补进 labels.json。
///
/// 用 `flutter_onnxruntime` 而不是 tflite：两个模型都是 ONNX，转换会掉精度，
/// 而量化实验证明这个分类模型对量化极其敏感（int8 直接掉到 0%）。
class ClosetVision {
  final OrtSession _seg;
  final OrtSession _vis;
  final Labels _labels;
  bool _closed = false;

  ClosetVision._(this._seg, this._vis, this._labels);

  /// 加载两个模型 + 标签。首次约 100~300 ms（模型从 asset 解到临时目录，
  /// 插件会缓存，第二次启动不再重复解压）。
  static Future<ClosetVision> load() async {
    final ort = OnnxRuntime();
    final seg = await ort.createSessionFromAsset('assets/models/seg.onnx');
    final vis = await ort.createSessionFromAsset('assets/models/vision.onnx');
    final raw = await rootBundle.loadString('assets/models/labels.json');
    return ClosetVision._(seg, vis, Labels.fromJson(raw));
  }

  Labels get labels => _labels;

  /// 一次解码，跑两次推理。任何一步失败都退化成 null，不抛给调用方 ——
  /// 自动能力坏掉不该让录入也坏掉。
  Future<VisionResult> analyze(Uint8List bytes) async {
    if (_closed) return const VisionResult();

    _Prep prep;
    try {
      prep = await Isolate.run(() => _prepBoth(bytes));
    } catch (e) {
      return VisionResult(maskRatio: 1, cls: null);
    }

    ByteData? mask;
    var ratio = 1.0;
    try {
      mask = await _segment(prep.seg);
      ratio = _onRatio(mask);
      if (!maskUsable(ratio)) mask = null;
    } catch (e) {
      if (kDebugMode) debugPrint('抠图失败：$e');
      mask = null;
      ratio = 1;
    }

    Classification? cls;
    try {
      cls = await _classify(prep.vis);
    } catch (e) {
      if (kDebugMode) debugPrint('分类失败：$e');
      cls = null;
    }

    return VisionResult(mask: mask, maskRatio: ratio, cls: cls);
  }

  Future<ByteData> _segment(Uint8List nhwc) async {
    final input = await OrtValue.fromList(nhwc, [1, kSegSide, kSegSide, 3]);
    try {
      final out = await _seg.run({_seg.inputNames.first: input});
      // u2netp 有 7 个输出，第 0 个是融合后的 d0，其余是侧输出，不读。
      final key = _seg.outputNames.first;
      final tensor = out[key];
      if (tensor == null) throw StateError('抠图没有输出');
      try {
        final flat = await tensor.asFlattenedList();
        final logits = Float32List(flat.length);
        for (var i = 0; i < flat.length; i++) {
          logits[i] = (flat[i] as num).toDouble();
        }
        final bytes = maskFromLogits(logits);
        return ByteData.view(bytes.buffer);
      } finally {
        for (final v in out.values) {
          await v.dispose();
        }
      }
    } finally {
      await input.dispose();
    }
  }

  double _onRatio(ByteData mask) {
    final total = mask.lengthInBytes;
    if (total == 0) return 0;
    var on = 0;
    for (var i = 0; i < total; i++) {
      if (mask.getUint8(i) > 127) on++;
    }
    return on / total;
  }

  Future<Classification> _classify(Uint8List nhwc) async {
    final input =
        await OrtValue.fromList(nhwc, [1, kVisionSide, kVisionSide, 3]);
    List<double> embedding;
    try {
      final out = await _vis.run({_vis.inputNames.first: input});
      final tensor = out.values.first;
      try {
        final flat = await tensor.asFlattenedList();
        embedding = l2Normalize(
          [for (final v in flat) (v as num).toDouble()],
        );
      } finally {
        for (final v in out.values) {
          await v.dispose();
        }
      }
    } finally {
      await input.dispose();
    }

    final keys = _labels.l1Keys;
    final scores = cosineScores(
      [for (final k in keys) _labels.l1Vector[k]!],
      embedding,
    );
    final order = List<int>.generate(scores.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final i1 = order[0];
    final i2 = order.length > 1 ? order[1] : order[0];
    final p1 = topProbability(scores);

    final l1Key = keys[i1];
    L2Score? l2;
    final entries = _labels.l2[l1Key];
    if (entries != null && entries.isNotEmpty) {
      final s2 = cosineScores([for (final e in entries) e.vector], embedding);
      final j = argMax(s2);
      l2 = L2Score(entries[j].name, topProbability(s2), j);
    }

    return Classification(
      top1: L1Score(l1Key, _labels.l1Label[l1Key] ?? l1Key, p1),
      top2:
          L1Score(keys[i2], _labels.l1Label[keys[i2]] ?? keys[i2], scores[i2]),
      l2: l2,
    );
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await _seg.close();
      await _vis.close();
    } catch (_) {
      // 关不掉不影响正确性，进程退出时系统会回收。
    }
  }
}

/// 一次解码出两种尺寸的 NHWC 像素。
///
/// 为什么合并：原图可能 4000×3000，解一次 JPEG 就要几百毫秒，
/// 分开做等于白解一次。推理本身在 platform channel 那头，
/// 解码+缩放留在 isolate 里，主线程只等结果。
class _Prep {
  final Uint8List seg;
  final Uint8List vis;
  const _Prep(this.seg, this.vis);
}

_Prep _prepBoth(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法解码图片');
  final base = img.bakeOrientation(decoded);
  return _Prep(
    _toNhwc(base, kSegSide, img.Interpolation.linear),
    _toNhwc(base, kVisionSide, img.Interpolation.cubic),
  );
}

Uint8List _toNhwc(img.Image base, int side, img.Interpolation interp) {
  // 直接拉伸到正方形。模型训练时就是 256×256 的方图，
  // 保持长宽比补边反而和训练分布不符（实测准确率略降）。
  final r =
      img.copyResize(base, width: side, height: side, interpolation: interp);
  final out = Uint8List(side * side * 3);
  var i = 0;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final p = r.getPixel(x, y);
      out[i++] = p.r.toInt();
      out[i++] = p.g.toInt();
      out[i++] = p.b.toInt();
    }
  }
  return out;
}
