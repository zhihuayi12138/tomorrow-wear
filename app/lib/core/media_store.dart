import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/db.dart';

const _uuid = Uuid();

/// 图片文件的落盘与回收。
///
/// 约定：数据库里只存**相对路径**（如 `img/orig/ab12.jpg`），
/// 绝对路径由 [absoluteImagePath] 在运行时拼出来。
/// 这样导出包和换设备都不会炸，见设计文档 §6.2。
class MediaStore {
  final ClosetDirs dirs;
  MediaStore(this.dirs);

  Future<void> ensureDirs() async {
    for (final d in [dirs.root, dirs.orig, dirs.proc, dirs.thumb, dirs.exportDir]) {
      final f = Directory(d);
      if (!await f.exists()) {
        await f.create(recursive: true);
      }
    }
  }

  /// 原图：换名保存，绝不覆盖用户来源文件。
  Future<String> saveOriginal(Uint8List bytes, {String ext = 'jpg'}) async {
    final name = '${_uuid.v4()}.$ext';
    final rel = p.join('img', 'orig', name);
    await File(p.join(dirs.root, rel)).writeAsBytes(bytes, flush: true);
    return rel;
  }

  Future<String> saveProcessed(Uint8List bytes) async {
    final name = '${_uuid.v4()}.jpg';
    final rel = p.join('img', 'proc', name);
    await File(p.join(dirs.root, rel)).writeAsBytes(bytes, flush: true);
    return rel;
  }

  Future<String> saveThumb(Uint8List bytes) async {
    final name = '${_uuid.v4()}.jpg';
    final rel = p.join('img', 'thumb', name);
    await File(p.join(dirs.root, rel)).writeAsBytes(bytes, flush: true);
    return rel;
  }

  /// 删除一批相对路径对应的文件。文件已经不存在时静默跳过。
  Future<void> deleteAll(Iterable<String> relPaths) async {
    for (final rel in relPaths) {
      if (rel.isEmpty) continue;
      final f = File(p.join(dirs.root, rel));
      try {
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // 删不掉不该阻断用户操作，最坏情况是留下一个孤儿文件。
      }
    }
  }

  String abs(String? rel) => rel == null ? '' : p.join(dirs.root, rel);
}
