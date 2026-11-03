import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P11 添加 / 编辑角色。
///
/// 名字是唯一必填项；身高、体重都可以留空，不阻断流程。
/// 刻意**没有**「这是对象/自己/家人」这类身份字段 ——
/// 角色之间的关系不产生任何权限或可见性差异，加了只是装饰。
class PersonEditPage extends ConsumerStatefulWidget {
  final Person? existing;
  const PersonEditPage({super.key, this.existing});

  @override
  ConsumerState<PersonEditPage> createState() => _PersonEditPageState();
}

class _PersonEditPageState extends ConsumerState<PersonEditPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _height = TextEditingController(
    text: widget.existing?.heightCm == null
        ? ''
        : widget.existing!.heightCm!.toStringAsFixed(0),
  );
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '改角色' : '添加角色'),
        leading: IconButton(
          icon: const Text('取消', style: TextStyle(fontSize: 15, color: AppColors.ink2)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.line),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add_a_photo_outlined, size: 22, color: AppColors.ink3),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('头像可以先不设，会用名字首字代替', style: AppTheme.label),
          ),
          const SizedBox(height: 26),
          const Text('名字', style: AppTheme.label),
          const SizedBox(height: 7),
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            decoration: const InputDecoration(hintText: '怎么称呼 ta'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('身高', style: AppTheme.label),
              const SizedBox(width: 6),
              Text('可留空', style: AppTheme.label),
            ],
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '—', suffixText: 'cm'),
          ),
          const SizedBox(height: 10),
          Text(
            '身高只在这里填一次，记录身材的时候不用重复问。',
            style: AppTheme.hint,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: _confirmDelete,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.up),
              child: const Text('删掉这个角色'),
            ),
            const SizedBox(height: 8),
            Text(
              'ta 的衣服和上身图会一起删掉，删了找不回来。',
              style: AppTheme.hint,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEdit ? '存下来' : '建好，去添加衣服'),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, '先填个名字');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final height = double.tryParse(_height.text.trim());

    if (_isEdit) {
      final p = widget.existing!;
      await repo.updatePerson(p.copyWith(
        name: name,
        heightCm: height,
        clearHeight: height == null,
      ));
    } else {
      final created = await repo.createPerson(name: name, heightCm: height);
      ref.read(currentPersonIdProvider.notifier).state = created.id;
    }
    ref.invalidate(personsProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删掉「${widget.existing!.name}」？'),
        content: const Text('ta 名下的所有衣服、上身图和身材记录都会一起删掉。'),
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
    await ref.read(repositoryProvider).deletePerson(widget.existing!.id);
    ref.invalidate(personsProvider);
    if (!mounted) return;
    // 角色列表 → 角色主页 → 编辑页，要退两层。
    Navigator.of(context).pop();
    Navigator.of(context).pop();
  }
}
