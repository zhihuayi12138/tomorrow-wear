import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P15 衣橱排序方式。
///
/// 四种都做成一眼能懂的说法：「最近加的」「最早加的」「按名称」「按类别」。
/// 不做「自定义拖动排序」—— 衣服数量会上百，手动排一遍比不排还累。
class SortModePage extends ConsumerWidget {
  const SortModePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(settingsProvider).valueOrNull?.sortMode ?? SortMode.newest;

    return Scaffold(
      appBar: AppBar(title: const Text('衣橱排序')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          for (final m in SortMode.values)
            InkWell(
              onTap: () => _pick(context, ref, current, m),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.label,
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.ink),
                          ),
                          const SizedBox(height: 3),
                          Text(_hintOf(m), style: AppTheme.label),
                        ],
                      ),
                    ),
                    if (m == current)
                      const Icon(Icons.check,
                          size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              '排序只作用在衣橱网格上。待确认队列按加入的先后排，'
              '因为那是要你逐件过一遍的地方，顺序乱了反而不好找。',
              style: AppTheme.hint,
            ),
          ),
        ],
      ),
    );
  }

  String _hintOf(SortMode m) {
    switch (m) {
      case SortMode.newest:
        return '默认。刚收进来的排在前面，适合刚开始整理的时候。';
      case SortMode.oldest:
        return '老衣服在前，适合回头翻「这件还在不在」。';
      case SortMode.name:
        return '按名字拼音排，同一类名字会挨在一起。';
      case SortMode.category:
        return '上装、下装、外套这样分组，翻起来像逛店。';
    }
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    SortMode current,
    SortMode next,
  ) async {
    if (next == current) return;
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    await ref
        .read(repositoryProvider)
        .saveSettings(settings.copyWith(sortMode: next));
    ref.invalidate(settingsProvider);
    if (context.mounted) showToast(context, '按${next.label}排');
  }
}
