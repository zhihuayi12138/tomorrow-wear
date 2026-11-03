import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../data/dao.dart';
import '../data/db.dart';
import '../models.dart';
import 'media_store.dart';

/// 导出/导入。格式见 `设计文档.md` §6.2。
///
/// 与文档的一处差别：`data.json` 里每张图多一个 `files` 映射
/// （`orig`/`processed`/`thumb` → zip 内的相对路径）。
/// 原因是原图可能是 png/webp，不能假定扩展名，而缺图又要能跳过。

class BackupCounts {
  final int persons, items, images, bodyRecords;
  const BackupCounts({
    required this.persons,
    required this.items,
    required this.images,
    required this.bodyRecords,
  });

  Map<String, Object?> toJson() => {
        'persons': persons,
        'items': items,
        'images': images,
        'bodyRecords': bodyRecords,
      };

  static BackupCounts fromJson(Map<String, Object?> m) => BackupCounts(
        persons: (m['persons'] as num?)?.toInt() ?? 0,
        items: (m['items'] as num?)?.toInt() ?? 0,
        images: (m['images'] as num?)?.toInt() ?? 0,
        bodyRecords: (m['bodyRecords'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      '$persons 个角色 · $items 件衣服 · $images 张图 · $bodyRecords 条身材记录';
}

class ExportResult {
  final File file;
  final BackupCounts counts;
  final int bytes;
  const ExportResult(this.file, this.counts, this.bytes);
}

class ExportService {
  final PersonDao persons;
  final ItemDao items;
  final ImageDao images;
  final BodyDao bodies;
  final MediaStore media;
  final ClosetDirs dirs;

  ExportService({
    required this.persons,
    required this.items,
    required this.images,
    required this.bodies,
    required this.media,
    required this.dirs,
  });

  Future<ExportResult> export() async {
    final allPersons = await persons.all();
    final archive = Archive();
    final itemJson = <Map<String, Object?>>[];
    final bodyJson = <Map<String, Object?>>[];
    final personJson = <Map<String, Object?>>[];
    var imageCount = 0;

    for (final person in allPersons) {
      // 头像单独打包：它不属于任何 item，但丢了换机后角色列表就全剩首字色块。
      String? avatarName;
      final avatarRel = person.avatarPath;
      if (avatarRel != null && avatarRel.isNotEmpty) {
        final file = File(media.abs(avatarRel));
        if (await file.exists()) {
          final ext =
              p.extension(avatarRel).isEmpty ? '.jpg' : p.extension(avatarRel);
          avatarName = 'avatars/${person.id}$ext';
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(avatarName, bytes.length, bytes));
        }
      }

      personJson.add({
        'id': person.id,
        'name': person.name,
        'heightCm': person.heightCm,
        'avatar': avatarName,
        'sortIndex': person.sortIndex,
        'createdAt': person.createdAt,
      });

      final personItems = await items.listForPerson(person.id);
      for (final item in personItems) {
        final imgs = await images.forItem(item.id);
        final imgsJson = <Map<String, Object?>>[];

        for (final im in imgs) {
          final files = <String, String>{};
          for (final entry in {
            'orig': im.origPath,
            'processed': im.processedPath,
            'thumb': im.thumbPath,
          }.entries) {
            final rel = entry.value;
            if (rel == null || rel.isEmpty) continue;
            final file = File(media.abs(rel));
            if (!await file.exists()) continue; // 缺图不阻断导出
            final ext = p.extension(rel).isEmpty ? '.jpg' : p.extension(rel);
            final name = 'images/${im.id}_${entry.key}$ext';
            final bytes = await file.readAsBytes();
            archive.addFile(ArchiveFile(name, bytes.length, bytes));
            files[entry.key] = name;
          }
          imgsJson.add({
            'id': im.id,
            'kind': im.kind.name,
            'useProcessed': im.useProcessed ? 1 : 0,
            'wornDate': im.wornDate,
            'note': im.note,
            'sortIndex': im.sortIndex,
            'createdAt': im.createdAt,
            'files': files,
          });
          imageCount++;
        }

        itemJson.add({
          'id': item.id,
          'personId': item.personId,
          'name': item.name,
          'categoryL1': item.categoryL1,
          'categoryL2': item.categoryL2,
          'colorHex': item.colorHex,
          'colorName': item.colorName,
          'seasons': item.seasons,
          'status': item.status.name,
          'confidence': item.confidence,
          'createdAt': item.createdAt,
          'updatedAt': item.updatedAt,
          'images': imgsJson,
        });
      }

      final records = await bodies.forPerson(person.id);
      for (final r in records) {
        bodyJson.add({
          'id': r.id,
          'personId': r.personId,
          'recordDate': r.recordDate,
          'weightKg': r.weightKg,
          'createdAt': r.createdAt,
          'values': r.values,
        });
      }
    }

    final counts = BackupCounts(
      persons: allPersons.length,
      items: itemJson.length,
      images: imageCount,
      bodyRecords: bodyJson.length,
    );

    final manifest = {
      'schemaVersion': kSchemaVersion,
      'appVersion': kAppVersion,
      'exportedAt': nowMs(),
      'counts': counts.toJson(),
    };

    final data = {
      'persons': personJson,
      'items': itemJson,
      'bodyRecords': bodyJson,
    };

    void addJson(String name, Object? payload) {
      final bytes =
          utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson('manifest.json', manifest);
    addJson('data.json', data);

    final bytes = ZipEncoder().encode(archive)!;
    final dir = Directory(dirs.exportDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = _stamp(DateTime.now());
    final out = File(p.join(dirs.exportDir, 'closet-backup-$stamp.zip'));
    await out.writeAsBytes(bytes, flush: true);
    return ExportResult(out, counts, bytes.length);
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }
}

/// 导入前先给用户看的内容：文件里有什么、能不能导。
class BackupPreview {
  final File file;
  final int schemaVersion;
  final String appVersion;
  final BackupCounts counts;
  const BackupPreview({
    required this.file,
    required this.schemaVersion,
    required this.appVersion,
    required this.counts,
  });

  bool get schemaTooNew => schemaVersion > kSchemaVersion;
}

class ImportResult {
  final int persons, items, images, bodyRecords;
  final int missingImages;
  final int skipped;
  const ImportResult({
    required this.persons,
    required this.items,
    required this.images,
    required this.bodyRecords,
    required this.missingImages,
    required this.skipped,
  });
}

enum ImportMode {
  /// 清空当前数据后全量导入。
  replace,

  /// 按 id 去重，已存在跳过。
  merge,
}

class ImportService {
  final ClosetDirs dirs;
  final MediaStore media;
  final PersonDao persons;
  final ItemDao items;
  final ImageDao images;
  final BodyDao bodies;

  ImportService({
    required this.dirs,
    required this.media,
    required this.persons,
    required this.items,
    required this.images,
    required this.bodies,
  });

  Future<({BackupPreview preview, Archive archive})> _load(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);

    ArchiveFile? find(String name) {
      for (final f in archive.files) {
        if (f.name == name) return f;
      }
      return null;
    }

    final mf = find('manifest.json');
    if (mf == null) {
      throw const FormatException('这个文件里没有 manifest.json，不是本 App 的备份包');
    }
    final manifest = jsonDecode(utf8.decode(mf.content as List<int>))
        as Map<String, Object?>;
    final preview = BackupPreview(
      file: file,
      schemaVersion: (manifest['schemaVersion'] as num?)?.toInt() ?? 0,
      appVersion: (manifest['appVersion'] as String?) ?? '未知',
      counts: BackupCounts.fromJson(
          (manifest['counts'] as Map?)?.cast<String, Object?>() ?? const {}),
    );
    return (preview: preview, archive: archive);
  }

  Future<BackupPreview> inspect(File file) async => (await _load(file)).preview;

  Future<ImportResult> run(File file, ImportMode mode) async {
    final loaded = await _load(file);
    if (loaded.preview.schemaTooNew) {
      throw FormatException(
          '这个备份来自更新版本的 App（schemaVersion ${loaded.preview.schemaVersion}），请先升级');
    }

    final archive = loaded.archive;
    ArchiveFile? find(String name) {
      for (final f in archive.files) {
        if (f.name == name) return f;
      }
      return null;
    }

    final dataFile = find('data.json');
    if (dataFile == null) {
      throw const FormatException('这个文件里没有 data.json');
    }
    final data = jsonDecode(utf8.decode(dataFile.content as List<int>))
        as Map<String, Object?>;

    if (mode == ImportMode.replace) {
      await _wipe();
    }

    var nPersons = 0, nItems = 0, nImages = 0, nBodies = 0;
    var missing = 0;
    var skipped = 0;

    final existingPersons = {for (final p in await persons.all()) p.id};
    final existingItems = <String>{};
    for (final pid in existingPersons) {
      for (final it in await items.listForPerson(pid)) {
        existingItems.add(it.id);
      }
    }

    // 角色
    for (final raw in (data['persons'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, Object?>();
      final id = m['id'] as String;
      if (existingPersons.contains(id)) {
        skipped++;
        continue;
      }

      String? avatarRel;
      final avatarName = m['avatar'] as String?;
      if (avatarName != null && avatarName.isNotEmpty) {
        final entry = find(avatarName);
        if (entry == null) {
          missing++;
        } else {
          final bytes = Uint8List.fromList(entry.content as List<int>);
          final ext = p.extension(avatarName).isEmpty
              ? 'jpg'
              : p.extension(avatarName).substring(1);
          avatarRel = await media.saveAvatar(bytes, ext: ext);
        }
      }

      final person = Person(
        id: id,
        name: (m['name'] as String?) ?? '未命名',
        avatarPath: avatarRel,
        heightCm: (m['heightCm'] as num?)?.toDouble(),
        sortIndex: (m['sortIndex'] as num?)?.toInt() ?? 0,
        createdAt: (m['createdAt'] as num?)?.toInt() ?? nowMs(),
      );
      await persons.insertRaw(person.toMap());
      existingPersons.add(id);
      nPersons++;
    }

    // 衣服与图片
    for (final raw in (data['items'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, Object?>();
      final itemId = m['id'] as String;
      if (existingItems.contains(itemId)) {
        skipped++;
        continue;
      }
      final personId = m['personId'] as String;
      if (!existingPersons.contains(personId)) {
        skipped++;
        continue;
      }

      final item = Item(
        id: itemId,
        personId: personId,
        name: (m['name'] as String?) ?? '未命名',
        categoryL1: (m['categoryL1'] as String?) ?? 'top',
        categoryL2: m['categoryL2'] as String?,
        colorHex: m['colorHex'] as String?,
        colorName: m['colorName'] as String?,
        seasons: ((m['seasons'] as List?) ?? const [kSeasonAll])
            .map((e) => e.toString())
            .toList(),
        status: (m['status'] as String?) == 'confirmed'
            ? ItemStatus.confirmed
            : ItemStatus.pending,
        confidence: (m['confidence'] as num?)?.toDouble(),
        createdAt: (m['createdAt'] as num?)?.toInt() ?? nowMs(),
        updatedAt: (m['updatedAt'] as num?)?.toInt() ?? nowMs(),
      );
      await items.insertRaw(item.toMap());
      existingItems.add(itemId);
      nItems++;

      for (final iraw in (m['images'] as List? ?? const [])) {
        final im = (iraw as Map).cast<String, Object?>();
        final files =
            (im['files'] as Map?)?.cast<String, Object?>() ?? const {};

        Future<String?> restore(String key) async {
          final path = files[key] as String?;
          if (path == null || path.isEmpty) return null;
          final entry = find(path);
          if (entry == null) {
            missing++;
            return null;
          }
          final bytes = Uint8List.fromList(entry.content as List<int>);
          final ext = p.extension(path).isEmpty
              ? 'jpg'
              : p.extension(path).substring(1);
          switch (key) {
            case 'orig':
              return media.saveOriginal(bytes, ext: ext);
            case 'processed':
              return media.saveProcessed(bytes);
            default:
              return media.saveThumb(bytes);
          }
        }

        final image = ItemImage(
          id: (im['id'] as String?) ?? '${itemId}_$nImages',
          itemId: itemId,
          kind: (im['kind'] as String?) == 'worn'
              ? ImageKind.worn
              : ImageKind.flat,
          origPath: await restore('orig'),
          processedPath: await restore('processed'),
          thumbPath: await restore('thumb'),
          useProcessed: ((im['useProcessed'] as num?)?.toInt() ?? 1) != 0,
          wornDate: (im['wornDate'] as num?)?.toInt(),
          note: im['note'] as String?,
          sortIndex: (im['sortIndex'] as num?)?.toInt() ?? 0,
          createdAt: (im['createdAt'] as num?)?.toInt() ?? nowMs(),
        );
        await images.add(image);
        nImages++;
      }
    }

    // 身材记录
    for (final raw in (data['bodyRecords'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, Object?>();
      final personId = m['personId'] as String;
      if (!existingPersons.contains(personId)) {
        skipped++;
        continue;
      }
      final values = ((m['values'] as Map?) ?? const {})
          .cast<String, Object?>()
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
      await bodies.upsertRaw(
        id: m['id'] as String,
        personId: personId,
        recordDate: (m['recordDate'] as num?)?.toInt() ?? nowMs(),
        weightKg: (m['weightKg'] as num?)?.toDouble() ?? 0,
        values: values,
        createdAt: (m['createdAt'] as num?)?.toInt() ?? nowMs(),
      );
      nBodies++;
    }

    return ImportResult(
      persons: nPersons,
      items: nItems,
      images: nImages,
      bodyRecords: nBodies,
      missingImages: missing,
      skipped: skipped,
    );
  }

  /// 替换模式：先摘掉全部数据，再顺手删掉旧图片文件。
  Future<void> _wipe() async {
    final rels = <String>[];
    for (final person in await persons.all()) {
      rels.addAll(await persons.collectImageFilesForPerson(person.id));
    }
    await persons.deleteAll();
    await media.deleteAll(rels);
  }
}
