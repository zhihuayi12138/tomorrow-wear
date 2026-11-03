import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup.dart';
import '../../data/db.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../person/person_page.dart';
import '../widgets/common.dart';
import 'category_page.dart';

/// P9 我的：导出、导入、分类体系、设置。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _stat('角色', stats?.persons),
                  _divider(),
                  _stat('衣服', stats?.items),
                  _divider(),
                  _stat('图片', stats?.images),
                ],
              ),
            ),
          ),
          const SectionTitle('备份'),
          _tile(
            context,
            icon: Icons.ios_share,
            title: '导出备份',
            subtitle: '打包成一个 zip，含全部图片和身材记录',
            onTap: () => _export(context, ref),
          ),
          _tile(
            context,
            icon: Icons.download_outlined,
            title: '从备份恢复',
            subtitle: '可以整个替换，也可以只把新东西合并进来',
            onTap: () => _import(context, ref),
          ),
          const SectionTitle('内容'),
          _tile(
            context,
            icon: Icons.account_tree_outlined,
            title: '分类体系',
            subtitle: '一级固定，二级可以自己加',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoryPage()),
            ),
          ),
          _tile(
            context,
            icon: Icons.people_outline,
            title: '管理角色',
            subtitle: '改名、改身高、删角色',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonListPage()),
            ),
          ),
          const SectionTitle('关于'),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              '明天穿什么 $kAppVersion\n'
              '这是一个服装相册：把衣服收进来、拍整齐、随时翻。\n'
              '不做推荐、不做虚拟试衣。',
              style: AppTheme.hint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int? value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value?.toString() ?? '—',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: AppTheme.label),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 0.6, height: 26, color: AppColors.line);

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppColors.ink2),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontSize: 14, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTheme.label),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 17, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在打包…')));
    try {
      final result = await ref.read(repositoryProvider).exportBackup();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('打包好了：${result.counts}')));
      await Share.shareXFiles([XFile(result.file.path)]);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;

    final file = File(path);
    BackupPreview preview;
    try {
      preview = await ref.read(repositoryProvider).inspectBackup(file);
    } catch (e) {
      if (context.mounted) showToast(context, '$e');
      return;
    }
    if (!context.mounted) return;

    final mode = await _askMode(context, preview);
    if (mode == null) return;

    try {
      final result =
          await ref.read(repositoryProvider).importBackup(file, mode);
      ref.invalidate(personsProvider);
      refreshLists(ref);
      if (!context.mounted) return;
      showToast(
        context,
        '导入了 ${result.items} 件衣服、${result.bodyRecords} 条记录'
        '${result.missingImages > 0 ? '，${result.missingImages} 张图缺失已跳过' : ''}',
      );
    } catch (e) {
      if (context.mounted) showToast(context, '导入失败：$e');
    }
  }

  Future<ImportMode?> _askMode(
      BuildContext context, BackupPreview preview) async {
    return showDialog<ImportMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这个备份里有什么'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${preview.counts}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text('备份格式版本 ${preview.schemaVersion}', style: AppTheme.label),
            const SizedBox(height: 16),
            Text(
              '「替换」会先清空现在全部数据，再导入备份里的内容。\n'
              '「合并」只把没见过的加进来，已有的跳过。',
              style: AppTheme.hint,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('算了')),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.merge),
            child: const Text('合并'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.replace),
            child: const Text('替换', style: TextStyle(color: AppColors.up)),
          ),
        ],
      ),
    );
  }
}
