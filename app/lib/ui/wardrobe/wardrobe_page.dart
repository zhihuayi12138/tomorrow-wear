import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../item/add_item_sheet.dart';
import '../item/item_detail_page.dart';
import '../person/person_page.dart';
import '../widgets/common.dart';
import 'pending_queue_page.dart';

/// P1 衣橱网格：当前角色的衣服，2~3 列正方形网格。
class WardrobePage extends ConsumerWidget {
  const WardrobePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(activePersonProvider);
    final persons = ref.watch(personsProvider);
    final pending = ref.watch(pendingItemsProvider).valueOrNull ?? const <Item>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('衣橱'),
        actions: [
          if (person != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: () => _openAdd(context, ref, person.id),
                icon: const Icon(Icons.add, size: 17),
                // fontSize 写在 Text 上而不是按钮的 style 里：按钮的 textStyle
                // 由主题统一给了 fontFamily，Text 只做增量覆盖，字体不会丢。
                label: const Text('添加衣服', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  // 不写 textStyle：写死一个没有 fontFamily 的 TextStyle 会整个
                  // 顶掉主题里的字体设置，golden 里那四个字就变方块。
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
      body: persons.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('读取失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.checkroom_outlined,
              title: '还没有角色',
              hint: '先建一个角色，再把 ta 的衣服收进来。\n每个人一个角色，衣服之间互不相通。',
              actionLabel: '建立第一个角色',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonListPage()),
              ),
            );
          }
          return _WardrobeBody(personId: person!.id, pendingCount: pending.length);
        },
      ),
    );
  }

  Future<void> _openAdd(BuildContext context, WidgetRef ref, String personId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddItemSheet(personId: personId),
    );
  }
}

class _WardrobeBody extends ConsumerWidget {
  final String personId;
  final int pendingCount;

  const _WardrobeBody({required this.personId, required this.pendingCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(wardrobeFilterProvider);
    final items = ref.watch(wardrobeItemsProvider);
    final covers = ref.watch(coversProvider).valueOrNull ?? const {};

    return CustomScrollView(
      slivers: [
        if (pendingCount > 0)
          SliverToBoxAdapter(
            child: _PendingBanner(count: pendingCount),
          ),
        SliverToBoxAdapter(child: _RoleTabs(currentId: personId)),
        SliverToBoxAdapter(
          child: _FilterBar(
            filter: filter,
            onChanged: (f) =>
                ref.read(wardrobeFilterProvider.notifier).state = f,
          ),
        ),
        items.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('读取失败：$e')),
          ),
          data: (list) {
            if (list.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: filter.isEmpty
                    ? EmptyState(
                        icon: Icons.checkroom_outlined,
                        title: '衣橱还是空的',
                        hint: '把衣服平铺在纯色桌面上、顺光拍一张，\n拍完还能逐件改错。',
                        actionLabel: '添加第一件衣服',
                        onAction: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (_) => AddItemSheet(personId: personId),
                        ),
                      )
                    : EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: '这个条件下没有衣服',
                        hint: '试试清掉筛选，或者换个类别看看。',
                        actionLabel: '清掉筛选',
                        onAction: () =>
                            ref.read(wardrobeFilterProvider.notifier).state =
                                const WardrobeFilter(),
                      ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: list.length,
                  (context, i) {
                    final item = list[i];
                    final cover = covers[item.id];
                    return _ItemTile(item: item, cover: cover);
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final int count;
  const _PendingBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PendingQueuePage()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF6EF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEFE2CE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.inbox_outlined, size: 17, color: AppColors.accent),
              const SizedBox(width: 9),
              Text(
                '$count 件待确认',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              const Text('去确认', style: TextStyle(fontSize: 12.5, color: AppColors.accent)),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// 角色横滑标签。按用户要求：切换角色而不分区展示。
class _RoleTabs extends ConsumerWidget {
  final String currentId;
  const _RoleTabs({required this.currentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persons = ref.watch(personsProvider).valueOrNull ?? const <Person>[];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        itemCount: persons.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == persons.length) {
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonListPage()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Icon(Icons.more_horiz, size: 17, color: AppColors.ink2),
              ),
            );
          }
          final p = persons[i];
          final selected = p.id == currentId;
          return GestureDetector(
            onTap: () {
              ref.read(currentPersonIdProvider.notifier).state = p.id;
            },
            onLongPress: () {
              ref.read(currentPersonIdProvider.notifier).state = p.id;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PersonPage(personId: p.id)),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.soft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p.name,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : AppColors.ink2,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final WardrobeFilter filter;
  final ValueChanged<WardrobeFilter> onChanged;

  const _FilterBar({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        children: [
          SoftChip(
            filter.isEmpty ? '全部' : '筛选 ${filter.activeCount}',
            selected: filter.isEmpty,
            onTap: () => _openFilterSheet(context, ref),
          ),
          const SizedBox(width: 8),
          for (final l1 in L1Category.all) ...[
            SoftChip(
              l1.label,
              selected: filter.categoryL1 == l1.code,
              onTap: () => onChanged(
                filter.categoryL1 == l1.code
                    ? filter.copyWith(clearCategory: true)
                    : filter.copyWith(categoryL1: l1.code),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _openFilterSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(initial: filter, onChanged: onChanged),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final WardrobeFilter initial;
  final ValueChanged<WardrobeFilter> onChanged;
  const _FilterSheet({required this.initial, required this.onChanged});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late WardrobeFilter f = widget.initial;
  late final TextEditingController _c =
      TextEditingController(text: widget.initial.query);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('筛选',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            TextField(
              controller: _c,
              decoration: const InputDecoration(hintText: '按名字搜索'),
              onChanged: (v) => setState(() => f = f.copyWith(query: v)),
            ),
            const SizedBox(height: 20),
            const Text('季节', style: AppTheme.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in Season.all)
                  SoftChip(
                    s.label,
                    selected: f.season == s.code,
                    onTap: () => setState(() => f = f.season == s.code
                        ? f.copyWith(clearSeason: true)
                        : f.copyWith(season: s.code)),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onChanged(const WardrobeFilter());
                      Navigator.of(context).pop();
                    },
                    child: const Text('全部清掉'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      widget.onChanged(f);
                      Navigator.of(context).pop();
                    },
                    child: const Text('看这些'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final Item item;
  final ItemImage? cover;

  const _ItemTile({required this.item, this.cover});

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(item.colorHex);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: item.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.tile,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // 网格只加载缩略图，禁止加载原图，见设计文档 §7。
                  child: ClosetImage(cover?.gridPath),
                ),
                if ((cover?.kind == ImageKind.worn))
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('无平铺图',
                          style: TextStyle(fontSize: 9, color: AppColors.ink3)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.line, width: 0.6),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  item.colorName ?? L1Category.labelOf(item.categoryL1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
