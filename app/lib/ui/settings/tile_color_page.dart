import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image_processor.dart';
import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P14 平铺图底色。
///
/// 每一档配一个真实的色块预览 —— 光看名字（米灰 / 纯白 / 浅灰）选不出来，
/// 因为它们只在「和衣服的对比」里才有意义。
class TileColorPage extends ConsumerWidget {
  const TileColorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider).valueOrNull?.tileColor ??
        TileOption.defaultKey;

    return Scaffold(
      appBar: AppBar(title: const Text('平铺图底色')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              '以后新加的衣服会用这个底色。\n已有的不动 —— 重算一遍要把几百张图重新处理，不值得。',
              style: AppTheme.hint,
            ),
          ),
          for (final opt in TileOption.all)
            _OptionRow(
              option: opt,
              selected: opt.key == current,
              onTap: () => _pick(context, ref, current, opt),
            ),
        ],
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    String current,
    TileOption opt,
  ) async {
    if (opt.key == current) return;
    final repo = ref.read(repositoryProvider);
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    await repo.saveSettings(settings.copyWith(tileColor: opt.key));
    ref.invalidate(settingsProvider);
    if (context.mounted) {
      showToast(context, '以后用${opt.label}');
    }
  }
}

class _OptionRow extends StatelessWidget {
  final TileOption option;
  final bool selected;
  final VoidCallback onTap;

  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            _Swatch(option: option),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(option.hint, style: AppTheme.label),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// 色块上叠两件衣服的剪影：一深一浅。
///
/// 只放一个纯色方块看不出问题 —— 浅色衣物会不会和底色融掉，
/// 得把浅色放在上面才看得出来。
class _Swatch extends StatelessWidget {
  final TileOption option;
  const _Swatch({required this.option});

  @override
  Widget build(BuildContext context) {
    Widget garment({required bool light}) => Container(
          width: 20,
          height: 26,
          decoration: BoxDecoration(
            color: light ? const Color(0xFFF7F5F1) : const Color(0xFF4A4A4A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: light ? AppColors.line : Colors.transparent,
              width: 0.8,
            ),
          ),
        );

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Color.fromARGB(
            255, option.normal.r, option.normal.g, option.normal.b),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          garment(light: false),
          const SizedBox(width: 4),
          garment(light: true),
        ],
      ),
    );
  }
}
