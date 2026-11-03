import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';

/// 缩略图/大图统一入口。
///
/// 一律走 [imageBytesProvider] 缓存，避免网格滚动时重复读盘。
/// 文件缺失（例如导入时缺图）显示占位，不抛错。
class ClosetImage extends ConsumerWidget {
  final String? relPath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? radius;

  const ClosetImage(
    this.relPath, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.radius,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (relPath == null || relPath!.isEmpty) {
      return _placeholder();
    }
    final bytes = ref.watch(imageBytesProvider(relPath!));
    return bytes.when(
      loading: () => _placeholder(),
      error: (_, __) => _placeholder(),
      data: (data) {
        if (data == null) return _placeholder();
        final child = Image.memory(
          data,
          fit: fit,
          width: width,
          height: height,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
        return radius == null
            ? child
            : ClipRRect(borderRadius: radius!, child: child);
      },
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.tile,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 18, color: AppColors.ink3),
    );
  }
}

/// 页面顶部的小标题（分组用）。
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 空态：一句话 + 一个主按钮。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.ink3),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center, style: AppTheme.hint),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 角色头像：有图用图，没图用名字首字 + 按 id 稳定的底色。
class PersonAvatar extends StatelessWidget {
  final Person person;
  final double size;

  const PersonAvatar(this.person, {super.key, this.size = 40});

  static const _palette = [
    Color(0xFFE3D6C8),
    Color(0xFFD8DDD2),
    Color(0xFFDBD5E0),
    Color(0xFFE0D8C6),
    Color(0xFFD3DBDF),
    Color(0xFFE4D3D1),
  ];

  Color get _bg {
    var h = 0;
    for (final c in person.id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final initial = person.name.isEmpty ? '?' : person.name.substring(0, 1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// 小圆角标签（类别、颜色、季节都用它）。
class SoftChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? dotColor;

  const SoftChip(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.soft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line, width: 0.6),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: selected ? Colors.white : AppColors.ink2,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把 `#RRGGBB` 转成 Color，失败返回 null。
Color? colorFromHex(String? hex) {
  if (hex == null || hex.length < 7) return null;
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

String formatDate(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${d.year}年${d.month}月${d.day}日';
}

String formatShortDate(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${d.month}月${d.day}日';
}

/// 统一的底部提示。
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
