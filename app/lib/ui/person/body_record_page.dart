import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P12 记录一次身材。
///
/// 设计要点（都在题目里吃过教训）：
/// 1. 选填 ≠ 一次全摊开，要按「人怎么量」分组：躯干 → 四肢 → 脚；
/// 2. 底部写「这次填了 4 / 15 项」，不写进度条 —— 进度条暗示必须填满；
/// 3. 身高不在本页重复问，只算 15 项（16 项里有 1 项在角色档案）；
/// 4. 三围不在录入时高亮对比差值，1cm 差异多半是量法误差。
class BodyRecordPage extends ConsumerStatefulWidget {
  final String personId;
  const BodyRecordPage({super.key, required this.personId});

  @override
  ConsumerState<BodyRecordPage> createState() => _BodyRecordPageState();
}

class _BodyRecordPageState extends ConsumerState<BodyRecordPage> {
  DateTime _date = DateTime.now();
  late final TextEditingController _weight = TextEditingController();
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    for (final f in BodyField.all) {
      _fields[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _filled =>
      _fields.values.where((c) => c.text.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(activePersonProvider);
    final records = ref.watch(bodyRecordsProvider(widget.personId)).valueOrNull ??
        const <BodyRecord>[];
    final last = records.isEmpty ? null : records.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记录一次身材'),
        leading: IconButton(
          icon: const Text('取消', style: TextStyle(fontSize: 15, color: AppColors.ink2)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '日期',
                      suffixIcon: Icon(Icons.calendar_today_outlined,
                          size: 15, color: AppColors.ink3),
                    ),
                    child: Text(
                      '${_date.year}年${_date.month}月${_date.day}日',
                      style: const TextStyle(fontSize: 14, color: AppColors.ink),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '体重',
                    suffixText: 'kg',
                    hintText: '必填',
                    // 输入框空的时候不显示「较上次 —」，那行字只会让人以为填错了。
                    helperText: last == null || _weight.text.trim().isEmpty
                        ? null
                        : '较上次 ${_weightDelta(last.weightKg)}',
                    helperStyle: AppTheme.label,
                  ),
                ),
              ),
            ],
          ),
          for (final group in BodyField.groupsInOrder()) ...[
            _GroupHeader(group: group, person: person),
            _fieldGrid(group),
          ],
          const SizedBox(height: 18),
          Text(
            '这次填了 $_filled / 15 项 · 身高在角色档案里，不用每次重复',
            style: AppTheme.label,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: FilledButton(
            onPressed: _save,
            child: const Text('存下来'),
          ),
        ),
      ),
    );
  }

  String _weightDelta(double lastValue) {
    final v = double.tryParse(_weight.text.trim());
    if (v == null) return '—';
    final d = v - lastValue;
    if (d.abs() < 0.05) return '±0';
    // ASCII 减号，不用 U+2212 —— 系统字体里不一定有这个字形。
    final sign = d > 0 ? '+' : '-';
    return '$sign${d.abs().toStringAsFixed(1)}';
  }

  Widget _fieldGrid(String group) {
    final fields = BodyField.all.where((f) => f.group == group).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Expanded(child: _cell(fields[i])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < fields.length ? _cell(fields[i + 1]) : const SizedBox(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(BodyField f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.label, style: const TextStyle(fontSize: 10.5, color: AppColors.ink3)),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: TextField(
            controller: _fields[f.key],
            textAlignVertical: TextAlignVertical.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: '未填',
              suffixText: f.unit,
              suffixStyle: const TextStyle(fontSize: 11, color: AppColors.ink3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weight.text.trim());
    if (weight == null || weight <= 0) {
      showToast(context, '体重必填，其他都能空着');
      return;
    }
    final values = <String, double>{};
    for (final f in BodyField.all) {
      final v = double.tryParse(_fields[f.key]!.text.trim());
      if (v != null) values[f.key] = v;
    }
    await ref.read(repositoryProvider).saveBodyRecord(
          personId: widget.personId,
          recordDate: _date.millisecondsSinceEpoch,
          weightKg: weight,
          values: values,
        );
    ref.invalidate(bodyRecordsProvider(widget.personId));
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast(context, '记下了');
  }
}

/// 组标题右侧不写装饰，写「这数据拿来干什么」。
class _GroupHeader extends StatelessWidget {
  final String group;
  final Person? person;
  const _GroupHeader({required this.group, this.person});

  String get _purpose => switch (group) {
        '躯干' => '胸/腰/臀对选上衣外套有用',
        '四肢' => '臂围/大腿围对选袖子裤子有用',
        '脚' => '会用在鞋的属性里',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            group,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          Text(_purpose, style: const TextStyle(fontSize: 10.5, color: AppColors.ink3)),
        ],
      ),
    );
  }
}

/// P7 身材记录详情：全部 16 项，三列对照。
///
/// 未填的项不隐藏、也不整行置灰，保留行写「未填」——
/// 表永远 16 行，补项时位置固定，不会跳。
class BodyRecordDetailPage extends ConsumerWidget {
  final String personId;
  final BodyRecord record;

  const BodyRecordDetailPage({
    super.key,
    required this.personId,
    required this.record,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persons = ref.watch(personsProvider).valueOrNull ?? const <Person>[];
    Person? person;
    for (final p in persons) {
      if (p.id == personId) person = p;
    }
    final records = ref.watch(bodyRecordsProvider(personId)).valueOrNull ??
        const <BodyRecord>[];
    BodyRecord? previous;
    for (var i = 0; i < records.length; i++) {
      if (records[i].id == record.id) {
        if (i + 1 < records.length) previous = records[i + 1];
        break;
      }
    }

    final rows = <(String, double?, double?, String)>[
      ('体重', record.weightKg, previous?.weightKg, 'kg'),
      ('身高', person?.heightCm, person?.heightCm, 'cm'),
      for (final f in BodyField.all)
        (f.label, record[f.key], previous?[f.key], f.unit),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('这次记录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Text(formatDate(record.recordDate),
                    style: const TextStyle(fontSize: 13, color: AppColors.ink2)),
                const Spacer(),
                Text('${record.filledCount} 项有值', style: AppTheme.label),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: AppColors.soft,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: const Row(
                    children: [
                      SizedBox(width: 72, child: Text('项目', style: AppTheme.label)),
                      Expanded(
                        child: Text('当次', textAlign: TextAlign.right, style: AppTheme.label),
                      ),
                      Expanded(
                        child: Text('上次', textAlign: TextAlign.right, style: AppTheme.label),
                      ),
                      SizedBox(
                        width: 62,
                        child: Text('变化', textAlign: TextAlign.right, style: AppTheme.label),
                      ),
                    ],
                  ),
                ),
                for (final r in rows) _DetailRow(r),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '变化列只在绝对值 ≥1 时写数字，1cm 以内视为量法误差。',
            style: AppTheme.hint,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final (String, double?, double?, String) data;
  const _DetailRow(this.data);

  @override
  Widget build(BuildContext context) {
    final (label, value, last, unit) = data;
    final delta = (value == null || last == null) ? null : value - last;

    return Container(
      height: 33,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line, width: 0.6)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
          ),
          Expanded(
            child: Text(
              value == null ? '未填' : '$value $unit',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: value == null ? AppColors.ink3 : AppColors.ink,
              ),
            ),
          ),
          Expanded(
            child: Text(
              last == null ? '—' : '$last',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              delta == null || delta.abs() < 1
                  ? '—'
                  : '${delta > 0 ? '+' : '-'}${delta.abs().toStringAsFixed(delta.abs() < 10 ? 1 : 0)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: delta == null || delta.abs() < 1
                    ? AppColors.ink3
                    : (delta < 0 ? AppColors.down : AppColors.up),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
