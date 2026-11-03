import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P8 身材趋势。
///
/// 三个刻意的取舍：
/// 1. **只画一条线**。体重和腰围量纲不同，画在一张图上要么双轴（没人看得懂），
///    要么归一化（读者看不出真实数字）。所以用切换指标。
/// 2. **不做回归/趋势预测**。三十天里涨跌 1kg 是水的波动，画一条预测线
///    会让人把噪声当趋势。
/// 3. **点少时不画线画点**。只有一次记录时一条线画不出来，
///    强行连成直线是编造数据。
class BodyTrendPage extends ConsumerStatefulWidget {
  final String personId;
  const BodyTrendPage({super.key, required this.personId});

  @override
  ConsumerState<BodyTrendPage> createState() => _BodyTrendPageState();
}

/// 可切换的指标。体重是唯一必填项，所以它永远有数据；
/// 其他项只有部分记录有值，缺值的那次不参与连线。
class _Metric {
  final String label;
  final String unit;
  final String? key;
  const _Metric(this.label, this.unit, this.key);

  static const weight = _Metric('体重', 'kg', null);

  static const all = <_Metric>[
    weight,
    _Metric('腰围', 'cm', 'waist_cm'),
    _Metric('胸围', 'cm', 'chest_cm'),
    _Metric('臀围', 'cm', 'hip_cm'),
    _Metric('大腿围', 'cm', 'thigh_cm'),
    _Metric('臂围', 'cm', 'arm_cm'),
  ];
}

class _BodyTrendPageState extends ConsumerState<BodyTrendPage> {
  _Metric _metric = _Metric.weight;

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(bodyRecordsProvider(widget.personId));
    final all = recordsAsync.valueOrNull ?? const <BodyRecord>[];

    // 图表一律按时间正序（老的在前），history 列表是倒序的，这里要反过来。
    final points = <(int, double)>[];
    for (final r in all) {
      final v = _metric.key == null ? r.weightKg : r[_metric.key!];
      if (v != null) points.add((r.recordDate, v));
    }
    points.sort((a, b) => a.$1.compareTo(b.$1));

    final usable = _Metric.all
        .where((m) => all.any((r) => m.key == null ? true : r[m.key!] != null))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('身材趋势'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              itemCount: usable.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final m = usable[i];
                return SoftChip(
                  m.label,
                  selected: m.label == _metric.label,
                  onTap: () => setState(() => _metric = m),
                );
              },
            ),
          ),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: EmptyState(
                icon: Icons.show_chart,
                title: '还没有${_metric.label}的数据',
                hint: '记过的记录里填了这项，这里才会有点。',
              ),
            )
          else ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Summary(metric: _metric, points: points),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 210,
                padding: const EdgeInsets.fromLTRB(6, 14, 12, 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TrendPainter(
                    points: points,
                    unit: _metric.unit,
                    dense: points.length > 6,
                    // CustomPaint 里的 TextPainter 不走 Theme 的字体级联，
                    // 不显式传就会落到默认字体上（测试里是 Ahem，全是方块）。
                    fontFamily:
                        Theme.of(context).textTheme.bodyMedium?.fontFamily,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                points.length < 2
                    ? '只有一次记录，先画一个点。再记一次就能看走向。'
                    : '横向是日期，纵向是${_metric.label}。点的间距按真实间隔算，不是等距。',
                style: AppTheme.hint,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 顶部三行摘要：最近值、这段时间的净变化、最高最低。
class _Summary extends StatelessWidget {
  final _Metric metric;
  final List<(int, double)> points;
  const _Summary({required this.metric, required this.points});

  @override
  Widget build(BuildContext context) {
    final first = points.first.$2;
    final last = points.last.$2;
    final delta = last - first;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _trim(last),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                  height: 1.05,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(metric.unit, style: AppTheme.label),
              ),
              const Spacer(),
              if (points.length >= 2)
                Text(
                  _deltaText(delta),
                  style: TextStyle(
                    fontSize: 13,
                    color: delta.abs() < 0.05
                        ? AppColors.ink3
                        : (delta < 0 ? AppColors.down : AppColors.up),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            points.length >= 2
                ? '${formatShortDate(points.first.$1)} 到现在 · ${points.length} 次记录 · '
                    '最低 ${_trim(_values.reduce(math.min))} 最高 ${_trim(_values.reduce(math.max))}'
                : '${formatShortDate(points.first.$1)} · 1 次记录',
            style: AppTheme.hint,
          ),
        ],
      ),
    );
  }

  List<double> get _values => points.map((e) => e.$2).toList();

  String _deltaText(double d) {
    if (d.abs() < 0.05) return '±0 ${metric.unit}';
    // ASCII 减号：U+2212 在系统黑体里没有字形。
    final sign = d > 0 ? '+' : '-';
    return '$sign${d.abs().toStringAsFixed(1)} ${metric.unit}';
  }
}

class _TrendPainter extends CustomPainter {
  final List<(int, double)> points;
  final String unit;
  final bool dense;
  final String? fontFamily;

  _TrendPainter({
    required this.points,
    required this.unit,
    required this.dense,
    this.fontFamily,
  });

  static const _leftPad = 34.0;
  static const _rightPad = 6.0;
  static const _topPad = 10.0;
  static const _bottomPad = 22.0;

  TextStyle _style({
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFamily: fontFamily,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _leftPad,
      _topPad,
      size.width - _rightPad,
      size.height - _bottomPad,
    );

    var lo = points.map((e) => e.$2).reduce(math.min);
    var hi = points.map((e) => e.$2).reduce(math.max);
    if (hi - lo < 0.5) {
      // 数据几乎一样时，把纵轴撑开一点，否则线贴在边上或被放大成噪音。
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    } else {
      final pad = (hi - lo) * 0.15;
      lo -= pad;
      hi += pad;
    }

    final t0 = points.first.$1;
    final t1 = points.last.$1;
    final span = math.max(t1 - t0, 1);

    Offset at(int i) {
      final (t, v) = points[i];
      final x =
          t1 == t0 ? plot.center.dx : plot.left + (t - t0) / span * plot.width;
      final y = plot.bottom - (v - lo) / (hi - lo) * plot.height;
      return Offset(x, y);
    }

    // 三条横向参考线 + 左右两端刻度，别的都不画。
    final gridPaint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 2; i++) {
      final y = plot.top + plot.height * i / 2;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);

      final v = hi - (hi - lo) * i / 2;
      _text(
        canvas,
        _trim(v),
        Offset(plot.left - 6, y),
        _style(size: 10, color: AppColors.ink3),
        alignRight: true,
        centerVertically: true,
      );
    }

    if (points.length >= 2) {
      final path = Path()..moveTo(at(0).dx, at(0).dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(at(i).dx, at(i).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < points.length; i++) {
      final o = at(i);
      canvas.drawCircle(o, 3.2, Paint()..color = Colors.white);
      canvas.drawCircle(
        o,
        3.2,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // 最后一个点标注数值，方便一眼看出「现在多少」。
    // 竖直方向留出 22px，是因为 10px 会正好压在点上面（字高约 13px）。
    // 点贴顶时改标在下方，否则会被裁掉；横向右对齐，避免压住折线。
    final last = at(points.length - 1);
    final labelY = last.dy - 22 >= 2 ? last.dy - 22 : last.dy + 8;
    _text(
      canvas,
      _trim(points.last.$2),
      Offset(plot.right, labelY),
      _style(size: 11, color: AppColors.ink, weight: FontWeight.w500),
      alignRight: true,
    );

    // 日期：点多了只标首尾，否则会挤成一团。
    _text(
      canvas,
      formatShortDate(points.first.$1),
      Offset(plot.left, size.height - 14),
      _style(size: 10, color: AppColors.ink3),
    );
    if (points.length >= 2) {
      _text(
        canvas,
        formatShortDate(points.last.$1),
        Offset(plot.right, size.height - 14),
        _style(size: 10, color: AppColors.ink3),
        alignRight: true,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style, {
    bool alignRight = false,
    bool centerVertically = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = anchor.dx;
    if (alignRight) dx -= tp.width;
    final dy = centerVertically ? anchor.dy - tp.height / 2 : anchor.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.unit != unit ||
      old.dense != dense ||
      old.fontFamily != fontFamily;
}

String _trim(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
