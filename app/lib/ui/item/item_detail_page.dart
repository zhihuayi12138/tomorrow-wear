import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P3 衣服详情。
///
/// 图片分两块且**顺序固定**：平铺图（处理版 + 原图）→ 上身图（原样保留）。
/// 平铺图可以「看原图 / 看处理图」切换 —— 分割失败时用户有出路。
class ItemDetailPage extends ConsumerWidget {
  final String itemId;
  const ItemDetailPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemProvider(itemId));
    final imagesAsync = ref.watch(itemImagesProvider(itemId));

    return itemAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('读取失败：$e')),
      ),
      data: (item) {
        final images = imagesAsync.valueOrNull ?? const <ItemImage>[];
        final flats = images.where((e) => e.kind == ImageKind.flat).toList();
        final worn = images.where((e) => e.kind == ImageKind.worn).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(item.name, overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 20),
                color: Colors.white,
                onSelected: (v) async {
                  if (v == 'delete') {
                    await _confirmDelete(context, ref, item);
                  } else if (v == 'edit') {
                    await _openEditSheet(context, item);
                  } else if (v == 'reflat') {
                    await _replaceFlat(context, ref, item);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('改属性')),
                  PopupMenuItem(value: 'reflat', child: Text('重传平铺图')),
                  PopupMenuItem(value: 'delete', child: Text('删掉这件衣服')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (flats.isNotEmpty)
                _FlatGallery(flats: flats)
              else
                _NoFlatHint(
                  onTap: () => _replaceFlat(context, ref, item),
                ),
              _AttributeCard(item: item),
              _WornSection(itemId: item.id, worn: worn),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () => _pickWorn(context, ref, item.id),
                  icon:
                      const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('上传一张上身效果图'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickWorn(
      BuildContext context, WidgetRef ref, String itemId) async {
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref
        .read(repositoryProvider)
        .addWornPhoto(itemId: itemId, bytes: bytes);
    ref.invalidate(itemImagesProvider(itemId));
    if (context.mounted) showToast(context, '上身图加好了');
  }

  /// 重传平铺图。
  ///
  /// 走确认框而不是直接替换：旧的那张会被删掉，拍错一次原来那张就没了。
  /// 名字/类别/季节都保留 —— 用户重传通常只是这张拍糊了。
  Future<void> _replaceFlat(
      BuildContext context, WidgetRef ref, Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('换一张平铺图？'),
        content: const Text(
          '原来那张会被删掉，找不回来。\n'
          '名字、类别、季节和上身图都不动。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('算了')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('换一张')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    if (context.mounted) showToast(context, '正在处理…');
    try {
      await ref
          .read(repositoryProvider)
          .replaceFlatPhoto(itemId: item.id, bytes: bytes);
      ref.invalidate(itemImagesProvider(item.id));
      ref.invalidate(itemProvider(item.id));
      refreshLists(ref);
      if (context.mounted) showToast(context, '换好了');
    } catch (e) {
      if (context.mounted) showToast(context, '没换成：$e');
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删掉这件衣服？'),
        content: const Text('平铺图和上身图会一起删掉，删了找不回来。'),
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
    await ref.read(repositoryProvider).deleteItem(item.id);
    refreshLists(ref);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _openEditSheet(BuildContext context, Item item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EditItemSheet(item: item),
    );
  }
}

class _FlatGallery extends ConsumerStatefulWidget {
  final List<ItemImage> flats;
  const _FlatGallery({required this.flats});

  @override
  ConsumerState<_FlatGallery> createState() => _FlatGalleryState();
}

class _FlatGalleryState extends ConsumerState<_FlatGallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final img = widget.flats[_index];
    final showOriginal = !img.useProcessed;
    final path = showOriginal
        ? (img.origPath ?? img.processedPath)
        : (img.processedPath ?? img.origPath);

    return Column(
      children: [
        // 高度固定为屏幕的 34%，不用 Expanded —— 否则会把下面的上身图挤出屏。
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.34,
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.tile,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: ClosetImage(path, fit: BoxFit.contain),
              ),
              if (img.processedPath != null)
                Positioned(
                  right: 24,
                  bottom: 10,
                  child: GestureDetector(
                    onTap: () async {
                      await ref.read(repositoryProvider).updateImage(
                            img.copyWith(useProcessed: !img.useProcessed),
                          );
                      ref.invalidate(itemImagesProvider(img.itemId));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            showOriginal
                                ? Icons.auto_awesome_outlined
                                : Icons.photo_outlined,
                            size: 13,
                            color: AppColors.ink2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            showOriginal ? '看处理图' : '看原图',
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.ink2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.flats.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.flats.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _index = i),
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.ink : AppColors.line,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AttributeCard extends ConsumerWidget {
  final Item item;
  const _AttributeCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    String? l2;
    for (final c in cats) {
      if (c.id == item.categoryL2) l2 = c.name;
    }
    final color = colorFromHex(item.colorHex);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(label: '名称', value: item.name),
          _Row(
            label: '类别',
            value:
                '${L1Category.labelOf(item.categoryL1)}${l2 == null ? '' : ' · $l2'}',
          ),
          _Row(
            label: '主色',
            value: item.colorName ?? '未识别',
            extra: color == null
                ? null
                : Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line, width: 0.6),
                    ),
                  ),
          ),
          _Row(
            label: '季节',
            value: item.seasons.map(Season.labelOf).join(' · '),
          ),
          const SizedBox(height: 6),
          Text(
            '拍的时候平铺在纯色桌面上、顺光，这样抠图最容易干净。',
            style: AppTheme.hint,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Widget? extra;
  const _Row({required this.label, required this.value, this.extra});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: AppTheme.label),
          ),
          if (extra != null) ...[extra!, const SizedBox(width: 5)],
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// 只有上身图、没有平铺图时的占位。
///
/// 这种衣服多半是从别处导进来的，或者当初拍的时候就只拍了上身照。
/// 给一个直接的补拍入口，别让用户摸到右上角的菜单里。
class _NoFlatHint extends StatelessWidget {
  final VoidCallback onTap;
  const _NoFlatHint({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: AppColors.soft,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_outlined, size: 24, color: AppColors.ink3),
              const SizedBox(height: 10),
              Text(
                '还没有平铺图',
                style: TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
              const SizedBox(height: 4),
              Text('点这里补一张，会自动抠图换底', style: AppTheme.hint),
            ],
          ),
        ),
      ),
    );
  }
}

class _WornSection extends ConsumerWidget {
  final String itemId;
  final List<ItemImage> worn;

  const _WornSection({required this.itemId, required this.worn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          '上身效果图',
          trailing: Text(
            worn.isEmpty ? '还没有' : '${worn.length} 张',
            style: AppTheme.label,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: worn.isEmpty
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.soft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '穿上这件拍了照，就传上来',
                        style: TextStyle(fontSize: 13, color: AppColors.ink2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '原图原样保存，只加一个日期',
                        style: AppTheme.hint,
                      ),
                    ],
                  ),
                )
              : SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: worn.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final im = worn[i];
                      return GestureDetector(
                        onTap: () => _editNote(context, ref, im),
                        onLongPress: () => _confirmDelete(context, ref, im),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 124,
                              height: 148,
                              decoration: BoxDecoration(
                                color: AppColors.tile,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              // 上身图不生成处理版，只显示原图。
                              child:
                                  ClosetImage(im.origPath, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              im.wornDate == null
                                  ? '未标日期'
                                  : formatShortDate(im.wornDate!),
                              style: AppTheme.label,
                            ),
                            const SizedBox(height: 1),
                            SizedBox(
                              width: 124,
                              child: Text(
                                (im.note == null || im.note!.isEmpty)
                                    ? '点一下写备注'
                                    : im.note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: (im.note == null || im.note!.isEmpty)
                                      ? AppColors.ink3
                                      : AppColors.ink2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ItemImage im) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删掉这张上身图？'),
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
    await ref.read(repositoryProvider).deleteImage(im);
    ref.invalidate(itemImagesProvider(itemId));
  }

  /// 备注编辑。
  ///
  /// 只给一个单行输入框，不给预置选项 —— 这是「今天配什么裤子穿的」那种
  /// 私人笔记，预置选项一定不够用。
  Future<void> _editNote(
      BuildContext context, WidgetRef ref, ItemImage im) async {
    final controller = TextEditingController(text: im.note ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这张图的备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            hintText: '比如：配那条牛仔裤穿的',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('算了')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('存下来'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;

    await ref.read(repositoryProvider).updateImage(
          im.copyWith(
              note: result.isEmpty ? null : result, clearNote: result.isEmpty),
        );
    ref.invalidate(itemImagesProvider(itemId));
  }
}

/// 改属性：名称、一级/二级类别、季节。
class EditItemSheet extends ConsumerStatefulWidget {
  final Item item;
  const EditItemSheet({super.key, required this.item});

  @override
  ConsumerState<EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends ConsumerState<EditItemSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.item.name);
  late String _l1 = widget.item.categoryL1;
  late String? _l2 = widget.item.categoryL2;
  late List<String> _seasons = List.of(widget.item.seasons);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byL1 = ref.watch(categoriesByL1Provider);
    final l2list = byL1[_l1] ?? const <Category>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('改属性',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: '名称')),
              const SizedBox(height: 18),
              const Text('一级类别', style: AppTheme.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in L1Category.all)
                    SoftChip(
                      c.label,
                      selected: _l1 == c.code,
                      onTap: () => setState(() {
                        _l1 = c.code;
                        _l2 = null;
                      }),
                    ),
                ],
              ),
              if (l2list.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('二级类别', style: AppTheme.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in l2list)
                      SoftChip(
                        c.name,
                        selected: _l2 == c.id,
                        onTap: () =>
                            setState(() => _l2 = _l2 == c.id ? null : c.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              const Text('季节', style: AppTheme.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in Season.all)
                    SoftChip(
                      s.label,
                      selected: _seasons.contains(s.code),
                      onTap: () => setState(() {
                        if (s.code == kSeasonAll) {
                          _seasons = [kSeasonAll];
                        } else {
                          _seasons.remove(kSeasonAll);
                          if (_seasons.contains(s.code)) {
                            _seasons.remove(s.code);
                          } else {
                            _seasons.add(s.code);
                          }
                          if (_seasons.isEmpty) _seasons = [kSeasonAll];
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  await ref.read(repositoryProvider).updateItem(
                        widget.item.copyWith(
                          name: name,
                          categoryL1: _l1,
                          categoryL2: _l2,
                          clearCategoryL2: _l2 == null,
                          seasons: _seasons,
                        ),
                      );
                  refreshLists(ref);
                  ref.invalidate(itemProvider(widget.item.id));
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('存下来'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
