import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// P4 拍照 / 选图 —— 新增一件衣服的入口。
///
/// 刻意做成两步：先选来源拍/选图，再填名字进「待确认」。
/// 不做「拍完直接入库」，因为自动分类一定会有错的时候。
class AddItemSheet extends ConsumerStatefulWidget {
  final String personId;
  const AddItemSheet({super.key, required this.personId});

  @override
  ConsumerState<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<AddItemSheet> {
  final List<_Draft> _drafts = [];
  final _picker = ImagePicker();
  bool _busy = false;
  bool _autoNamed = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('添加衣服',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                '平铺在纯色桌面上、顺光拍。背景干净，抠出来才干净。',
                style: AppTheme.hint,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('拍一张'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('从相册选'),
                    ),
                  ),
                ],
              ),
            ),
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('待添加', style: AppTheme.label),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _drafts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final d = _drafts[i];
                    return Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: AppColors.tile,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.memory(d.bytes,
                                  fit: BoxFit.cover, gaplessPlayback: true),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              width: 96,
                              child: Text(
                                d.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.label,
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _drafts.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (_drafts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Row(
                  children: [
                    Checkbox(
                      value: _autoNamed,
                      onChanged: (v) => setState(() => _autoNamed = v ?? true),
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Text('自动起名（拍完还能改）', style: AppTheme.hint),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: FilledButton(
                onPressed: _drafts.isEmpty || _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_drafts.isEmpty
                        ? '先拍或选一张'
                        : '处理这 ${_drafts.length} 件并加入待确认'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    List<XFile> picked;
    if (source == ImageSource.camera) {
      final one = await _picker.pickImage(source: source, imageQuality: 92);
      picked = one == null ? const [] : [one];
    } else {
      picked = await _picker.pickMultiImage(imageQuality: 92);
    }
    if (picked.isEmpty) return;

    for (final f in picked) {
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _drafts.add(_Draft(
          bytes: bytes,
          name: '新衣服 ${_drafts.length + 1}',
        ));
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    var n = 0;
    for (final d in _drafts) {
      final index = n + 1;
      await repo.addFlatPhoto(
        personId: widget.personId,
        bytes: d.bytes,
        name: _autoNamed ? '待确认 $index' : d.name,
      );
      n++;
    }
    refreshLists(ref);
    ref.invalidate(pendingItemsProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast(context, '$n 件进了待确认，翻一遍就能入衣橱');
  }
}

class _Draft {
  final Uint8List bytes;
  final String name;
  const _Draft({required this.bytes, required this.name});
}
