import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../item/item_detail_page.dart';
import '../widgets/common.dart';

/// P2 待确认队列。
///
/// 这里是「录入必须快」和「不能静默入库」的折中：
/// 批量拍完先落到这里，用户翻一遍、改错、确认，才进正式衣橱。
class PendingQueuePage extends ConsumerWidget {
  const PendingQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(activePersonProvider);
    final items = ref.watch(pendingItemsProvider);
    final covers = ref.watch(coversProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('待确认'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('读取失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.done_all,
              title: '都确认完了',
              hint: '新拍的衣服会先出现在这里，等你过一遍再进衣橱。',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${list.length} 件等你过一遍',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      '类别有疑问的会标出来',
                      style: AppTheme.label,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = list[i];
                    return _PendingCard(
                      item: item,
                      cover: covers[item.id],
                      personId: person?.id ?? '',
                      isLast: i == list.length - 1,
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: FilledButton(
                    onPressed: () async {
                      if (person == null) return;
                      await ref.read(repositoryProvider).confirmAll(person.id);
                      refreshLists(ref);
                      ref.invalidate(pendingItemsProvider);
                      if (context.mounted) {
                        showToast(context, '${list.length} 件都进衣橱了');
                      }
                    },
                    child: Text('全部确认 ${list.length} 件'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  final Item item;
  final ItemImage? cover;
  final String personId;
  final bool isLast;

  const _PendingCard({
    required this.item,
    required this.cover,
    required this.personId,
    required this.isLast,
  });

  /// 置信度低于 0.45 才提示，否则用户会被无意义的提示淹没。
  bool get _lowConfidence => (item.confidence ?? 1) < 0.45;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = colorFromHex(item.colorHex);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openDetail(context),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.tile,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: ClosetImage(cover?.gridPath),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _rename(context, ref),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.edit_outlined, size: 15, color: AppColors.ink3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _openDetail(context),
                  child: Row(
                    children: [
                      SoftChip(
                        L1Category.labelOf(item.categoryL1),
                        selected: false,
                        onTap: () => _openDetail(context),
                      ),
                      if (item.categoryL2 != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _l2Name(ref, item.categoryL2!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.label,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_lowConfidence) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 13, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        '类别拿不准，点一下改',
                        style: TextStyle(fontSize: 11.5, color: AppColors.accent),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (color != null) ...[
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line, width: 0.6),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(item.colorName ?? '—', style: AppTheme.label),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      item.seasons.map(Season.labelOf).join('·'),
                      style: AppTheme.label,
                    ),
                    const Spacer(),
                    _MiniButton(
                      label: '确认',
                      filled: true,
                      onTap: () async {
                        await ref.read(repositoryProvider).updateItem(
                              item.copyWith(status: ItemStatus.confirmed),
                            );
                        refreshLists(ref);
                        ref.invalidate(pendingItemsProvider);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _l2Name(WidgetRef ref, String id) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    for (final c in cats) {
      if (c.id == id) return c.name;
    }
    return '';
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: item.id)),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('改个名字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '比如「灰色卫衣」'),
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
    if (name == null || name.isEmpty) return;
    await ref.read(repositoryProvider).updateItem(item.copyWith(name: name));
    refreshLists(ref);
    ref.invalidate(pendingItemsProvider);
    ref.invalidate(itemProvider(item.id));
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _MiniButton({required this.label, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: filled ? null : Border.all(color: AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: filled ? Colors.white : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}
