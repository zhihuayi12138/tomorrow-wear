import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P10 分类体系：一级写死、二级可自建。
///
/// 自建标签用褐色、可删；内置灰色、只能改名。
/// 删除自建类别时明确告诉用户「N 件衣服会退回到一级类别」——
/// 不说清楚，用户会以为衣服也被删了。
class CategoryPage extends ConsumerWidget {
  const CategoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byL1 = ref.watch(categoriesByL1Provider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类体系'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 14),
            child: Text(
              '一级类别固定七个，二级可以自己加。加完立刻能被识别用到。',
              style: AppTheme.hint,
            ),
          ),
          for (final l1 in L1Category.all)
            _L1Group(l1: l1, categories: byL1[l1.code] ?? const <Category>[]),
          const SizedBox(height: 18),
          const _CustomSection(),
        ],
      ),
    );
  }
}

class _L1Group extends ConsumerWidget {
  final L1Category l1;
  final List<Category> categories;
  const _L1Group({required this.l1, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = categories.where((c) => !c.isBuiltin).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            l1.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
          subtitle: Text(
            '${categories.length} 个二级${custom > 0 ? ' · $custom 个自建' : ''}',
            style: AppTheme.label,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    _CategoryChip(category: c),
                  GestureDetector(
                    onTap: () => _add(context, ref, l1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 13, color: AppColors.ink3),
                          SizedBox(width: 3),
                          Text('加一个', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, L1Category l1) async {
    final name = await _promptName(context, '在「${l1.label}」下加一个');
    if (name == null || name.isEmpty) return;
    await ref.read(repositoryProvider).createCategory(l1: l1.code, name: name);
    ref.invalidate(categoriesProvider);
  }
}

class _CategoryChip extends ConsumerWidget {
  final Category category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builtin = category.isBuiltin;
    return GestureDetector(
      onTap: () => _showActions(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: builtin ? AppColors.soft : const Color(0xFFFBF3EA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          category.name,
          style: TextStyle(
            fontSize: 12,
            color: builtin ? AppColors.ink2 : AppColors.accent,
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(category.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (category.isBuiltin)
                    const Text('内置', style: AppTheme.label),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, size: 19),
              title: const Text('改名'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (!category.isBuiltin)
              ListTile(
                leading: const Icon(Icons.delete_outline, size: 19, color: AppColors.up),
                title: const Text('删掉', style: TextStyle(color: AppColors.up)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'rename') {
      final name = await _promptName(context, '改个名字', initial: category.name);
      if (name == null || name.isEmpty) return;
      await ref.read(repositoryProvider).renameCategory(category.id, name);
      ref.invalidate(categoriesProvider);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final count = await ref.read(repositoryProvider).countItemsInCategory(category.id);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删掉「${category.name}」？'),
        content: Text(
          count == 0
              ? '还没有衣服用它，删了不影响任何东西。'
              : '$count 件衣服会退回到一级类别，衣服本身不删。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('算了')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删掉', style: TextStyle(color: AppColors.up)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).deleteCategory(category.id);
    ref.invalidate(categoriesProvider);
    refreshLists(ref);
    if (context.mounted) {
      showToast(context, count == 0 ? '删掉了' : '$count 件衣服已退回一级类别');
    }
  }
}

/// 底部单独一块「我自建的」，集中管理。
class _CustomSection extends ConsumerWidget {
  const _CustomSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final mine = all.where((c) => !c.isBuiltin).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('我自建的',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              const SizedBox(width: 6),
              if (mine.isNotEmpty)
                Text('${mine.length} 个',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
            ],
          ),
          const SizedBox(height: 10),
          if (mine.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('还没有。上面的「加一个」建出来的会集中在这里。',
                  style: AppTheme.hint),
            )
          else
            for (final c in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(c.name, style: const TextStyle(fontSize: 12.5, color: AppColors.ink2)),
                    const SizedBox(width: 8),
                    Text('· ${L1Category.labelOf(c.l1)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        final name =
                            await _promptName(context, '改个名字', initial: c.name);
                        if (name == null || name.isEmpty) return;
                        await ref.read(repositoryProvider).renameCategory(c.id, name);
                        ref.invalidate(categoriesProvider);
                      },
                      child: const Text('改名',
                          style: TextStyle(fontSize: 11.5, color: AppColors.accent)),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        final count = await ref
                            .read(repositoryProvider)
                            .countItemsInCategory(c.id);
                        if (!context.mounted) return;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('删掉「${c.name}」？'),
                            content: Text(count == 0
                                ? '还没有衣服用它。'
                                : '$count 件衣服会退回到一级类别，衣服本身不删。'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('算了')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('删掉',
                                      style: TextStyle(color: AppColors.up))),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await ref.read(repositoryProvider).deleteCategory(c.id);
                        ref.invalidate(categoriesProvider);
                        refreshLists(ref);
                      },
                      child: const Text('删除',
                          style: TextStyle(fontSize: 11.5, color: AppColors.up)),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context, String title, {String? initial}) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '比如「背心」「吊带」'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('好'),
        ),
      ],
    ),
  );
  return result;
}
