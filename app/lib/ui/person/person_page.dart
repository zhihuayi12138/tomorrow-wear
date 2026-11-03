import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'body_record_page.dart';
import 'body_trend_page.dart';
import 'person_edit_page.dart';

/// P5 角色列表 + P6 角色主页（身材档案摘要）。
///
/// 按用户要求：衣服按角色隔开、互不相通，所以角色不是标签而是边界。
class PersonListPage extends ConsumerWidget {
  const PersonListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persons = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('角色'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          if (_hasEnoughToSort(persons))
            IconButton(
              tooltip: '排序',
              icon: const Icon(Icons.swap_vert, size: 20),
              onPressed: () {
                final list = persons.valueOrNull ?? const <Person>[];
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => PersonSortPage(persons: list)),
                );
              },
            ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonEditPage()),
            ),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('添加角色', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              // 不要在这里写 textStyle：会顶掉主题里的 fontFamily。
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      body: persons.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('读取失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.person_outline,
              title: '还没有角色',
              hint: '一个人一个角色。ta 的衣服只出现在 ta 的衣橱里。',
              actionLabel: '建立第一个角色',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonEditPage()),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _PersonCard(person: list[i]),
          );
        },
      ),
    );
  }
}

/// 角色卡右侧的「⋯」：改名 / 删角色。
///
/// 删除入口刻意放在列表上而不是只放在编辑页里 ——
/// 编辑页要先点进角色主页再点设置，两步才找得到「怎么删一个人」。
class _CardMenu extends ConsumerWidget {
  final Person person;
  const _CardMenu({required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, size: 20, color: AppColors.ink3),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onSelected: (v) async {
        if (v == 'edit') {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PersonEditPage(existing: person)),
          );
        } else if (v == 'delete') {
          await _confirmDelete(context, ref);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(value: 'edit', child: Text('改名字和头像')),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('删掉这个角色', style: TextStyle(color: AppColors.up)),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final itemCount = (await repo.loadItems(person.id)).length;

    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删掉「${person.name}」？'),
        content: Text(itemCount == 0
            ? 'ta 的名下还没有衣服。'
            : 'ta 名下的 $itemCount 件衣服、所有上身图和身材记录都会一起删掉，删了找不回来。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('算了')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删掉', style: TextStyle(color: AppColors.up)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await repo.deletePerson(person.id);
    ref.invalidate(personsProvider);
    // 删掉的正是当前选中的角色时，把选择清空，否则衣橱会停在旧 id 上。
    if (ref.read(currentPersonIdProvider) == person.id) {
      ref.read(currentPersonIdProvider.notifier).state = null;
    }
    refreshLists(ref);
    if (!context.mounted) return;
    showToast(context, '删掉了「${person.name}」');
  }
}

bool _hasEnoughToSort(AsyncValue<List<Person>> persons) =>
    (persons.valueOrNull?.length ?? 0) >= 2;

class _PersonCard extends ConsumerWidget {
  final Person person;
  const _PersonCard({required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(bodyRecordsProvider(person.id)).valueOrNull;
    final latest =
        (records != null && records.isNotEmpty) ? records.first : null;

    return GestureDetector(
      onTap: () {
        ref.read(currentPersonIdProvider.notifier).state = person.id;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PersonPage(personId: person.id)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            PersonAvatar(person, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle(latest),
                    style: AppTheme.label,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
            _CardMenu(person: person),
          ],
        ),
      ),
    );
  }

  String _subtitle(BodyRecord? latest) {
    final bits = <String>[];
    if (person.heightCm != null) {
      bits.add('${person.heightCm!.toStringAsFixed(0)}cm');
    }
    if (latest != null) {
      bits.add('${latest.weightKg.toStringAsFixed(1)}kg');
      bits.add(formatShortDate(latest.recordDate));
    }
    if (bits.isEmpty) return '还没有身材记录';
    return bits.join(' · ');
  }
}

/// 角色排序：长按拖动，松手即存。
///
/// 用独立的整页而不是列表内的拖动，是因为列表同时是「进入角色」的入口 ——
/// 两者抢同一个手势，用户会拖不动也点不准。
class PersonSortPage extends ConsumerStatefulWidget {
  final List<Person> persons;
  const PersonSortPage({super.key, required this.persons});

  @override
  ConsumerState<PersonSortPage> createState() => _PersonSortPageState();
}

class _PersonSortPageState extends ConsumerState<PersonSortPage> {
  late final List<Person> _list = [...widget.persons];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调整顺序'),
        leading: IconButton(
          icon: const Text('取消',
              style: TextStyle(fontSize: 15, color: AppColors.ink2)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('存下来', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('长按拖动。顺序就是衣橱里角色标签的顺序。', style: AppTheme.hint),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _list.length,
              // 用 onReorderItem 而不是已废弃的 onReorder：
              // 它已经把「移除后索引要减一」算好了，不用自己再判 to > from。
              onReorderItem: (from, to) {
                setState(() {
                  final p = _list.removeAt(from);
                  _list.insert(to, p);
                });
              },
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
              itemBuilder: (context, i) {
                final p = _list[i];
                return Padding(
                  key: ValueKey(p.id),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        PersonAvatar(p, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const Icon(Icons.drag_handle,
                            size: 20, color: AppColors.ink3),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(repositoryProvider)
        .reorderPersons(_list.map((e) => e.id).toList());
    ref.invalidate(personsProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast(context, '顺序存好了');
  }
}

/// P6 角色主页：身材档案摘要 + 历史列表 + 入口。
class PersonPage extends ConsumerWidget {
  final String personId;
  const PersonPage({super.key, required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persons = ref.watch(personsProvider).valueOrNull ?? const <Person>[];
    Person? person;
    for (final p in persons) {
      if (p.id == personId) person = p;
    }
    if (person == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('角色不存在')),
      );
    }

    final recordsAsync = ref.watch(bodyRecordsProvider(personId));
    final records = recordsAsync.valueOrNull ?? const <BodyRecord>[];
    final latest = records.isEmpty ? null : records.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 19),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PersonEditPage(existing: person),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                PersonAvatar(person, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        person.heightCm == null
                            ? '身高还没填'
                            : '身高 ${person.heightCm!.toStringAsFixed(0)} cm',
                        style: AppTheme.label,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(
            '现在的身材',
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BodyRecordPage(personId: personId),
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.accent,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('记一次', style: TextStyle(fontSize: 12.5)),
                  Icon(Icons.chevron_right, size: 14),
                ],
              ),
            ),
          ),
          if (latest == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text('还没有记录',
                        style:
                            TextStyle(fontSize: 13.5, color: AppColors.ink2)),
                    const SizedBox(height: 5),
                    Text(
                      '只填体重也能存，其他 14 项全是选填',
                      style: AppTheme.hint,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _LatestGrid(record: latest, heightCm: person.heightCm),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RestCard(record: latest),
            ),
          ],
          SectionTitle(
            '历史',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (records.isNotEmpty)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BodyTrendPage(personId: personId),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.show_chart,
                            size: 14, color: AppColors.accent),
                        SizedBox(width: 3),
                        Text('看趋势',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.accent)),
                      ],
                    ),
                  ),
                if (records.isNotEmpty) const SizedBox(width: 12),
                Text(
                  records.isEmpty ? '' : '${records.length} 次',
                  style: AppTheme.label,
                ),
              ],
            ),
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('记了才会出现在这里。', style: AppTheme.hint),
            )
          else
            for (var i = 0; i < records.length; i++)
              _HistoryRow(
                record: records[i],
                previous: i + 1 < records.length ? records[i + 1] : null,
                personId: personId,
              ),
        ],
      ),
    );
  }
}

/// 首屏 6 格大数字：身高/体重/腰围/胸围/臀围/大腿围。
class _LatestGrid extends StatelessWidget {
  final BodyRecord record;
  final double? heightCm;
  const _LatestGrid({required this.record, this.heightCm});

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      ('身高', heightCm == null ? '—' : heightCm!.toStringAsFixed(0)),
      ('体重', record.weightKg.toStringAsFixed(1)),
      ('腰围', _v(record, 'waist_cm')),
      ('胸围', _v(record, 'chest_cm')),
      ('臀围', _v(record, 'hip_cm')),
      ('大腿围', _v(record, 'thigh_cm')),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) Expanded(child: _cell(cells[i])),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 3; i < 6; i++) Expanded(child: _cell(cells[i])),
            ],
          ),
        ],
      ),
    );
  }

  String _v(BodyRecord r, String key) {
    final v = r[key];
    return v == null ? '—' : _trim(v);
  }

  Widget _cell((String, String) c) {
    return Column(
      children: [
        Text(
          c.$2,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w500,
            color: c.$2 == '—' ? AppColors.ink3 : AppColors.ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(c.$1, style: AppTheme.label),
      ],
    );
  }
}

/// 其余 10 项，用小字双列，右上角「全部 16 项」是出口。
class _RestCard extends ConsumerWidget {
  final BodyRecord record;
  const _RestCard({required this.record});

  static const _keys = [
    ('下胸围', 'underbust_cm'),
    ('肩宽', 'shoulder_cm'),
    ('背长', 'back_cm'),
    ('小腿围', 'calf_cm'),
    ('臂围', 'arm_cm'),
    ('颈围', 'neck_cm'),
    ('臂长', 'arm_len_cm'),
    ('腿长', 'leg_cm'),
    ('鞋码', 'shoe_size_cn'),
    ('脚长', 'foot_len_mm'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('其余 10 项', style: AppTheme.label),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BodyRecordDetailPage(
                        personId: record.personId, record: record),
                  ),
                ),
                child: Row(
                  children: [
                    Text('全部 16 项',
                        style:
                            TextStyle(fontSize: 11.5, color: AppColors.accent)),
                    const Icon(Icons.chevron_right,
                        size: 14, color: AppColors.accent),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 26,
            runSpacing: 9,
            children: [
              for (final (label, key) in _keys)
                SizedBox(
                  // 宽度固定，避免「未填」和右值粘连读成「未填 肩宽 38」。
                  width: 108,
                  child: Row(
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.ink3)),
                      const Spacer(),
                      Text(
                        record[key] == null ? '未填' : _trim(record[key]!),
                        style: TextStyle(
                          fontSize: 11,
                          color: record[key] == null
                              ? AppColors.ink3
                              : AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  final BodyRecord record;
  final BodyRecord? previous;
  final String personId;

  const _HistoryRow({
    required this.record,
    required this.previous,
    required this.personId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delta =
        previous == null ? null : record.weightKg - previous!.weightKg;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              BodyRecordDetailPage(personId: personId, record: record),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Text(
              formatShortDate(record.recordDate),
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            const SizedBox(width: 10),
            Text('${record.filledCount} 项', style: AppTheme.label),
            const Spacer(),
            Text(
              '${record.weightKg.toStringAsFixed(1)} kg',
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            if (delta != null) ...[
              const SizedBox(width: 8),
              Text(
                _deltaText(delta),
                style: TextStyle(
                  fontSize: 12,
                  color: delta.abs() < 0.05
                      ? AppColors.ink3
                      : (delta < 0 ? AppColors.down : AppColors.up),
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  String _deltaText(double d) {
    if (d.abs() < 0.05) return '±0';
    // 用 ASCII 的减号，不要用 U+2212：系统黑体里没有这个字形，真机上一样会掉。
    final sign = d > 0 ? '+' : '-';
    return '$sign${d.abs().toStringAsFixed(1)}';
  }
}

String _trim(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
