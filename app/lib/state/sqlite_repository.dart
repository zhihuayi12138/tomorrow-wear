import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/backup.dart';
import '../core/image_processor.dart';
import '../core/media_store.dart';
import '../data/dao.dart';
import '../data/db.dart';
import '../models.dart';
import 'repository.dart';

const _uuid = Uuid();

/// 真实实现：sqflite + 文件系统。
class SqliteRepository implements ClosetRepository {
  Database? _db;
  ClosetDirs? _dirs;
  MediaStore? _media;

  PersonDao? _persons;
  ItemDao? _items;
  ImageDao? _images;
  BodyDao? _bodies;
  CategoryDao? _categories;
  MetaDao? _metas;

  /// 处理管线没有分割模型时传 null —— 此时只做统一排版，不抠背景。
  /// 这是 M1 的既定状态，见设计文档 §8。
  final ByteData? Function(Uint8List bytes)? segmenter;

  SqliteRepository({this.segmenter});

  @override
  Future<void> warmUp() async {
    if (_db != null) return;

    final support = await getApplicationSupportDirectory();
    final root = '${support.path}${Platform.pathSeparator}closet';
    final dirs = ClosetDirs(root);

    final media = MediaStore(dirs);
    await media.ensureDirs();

    final db = await openClosetDb(dirs.dbFile);

    _dirs = dirs;
    _media = media;
    _db = db;
    _persons = PersonDao(db);
    _items = ItemDao(db);
    _images = ImageDao(db);
    _bodies = BodyDao(db);
    _categories = CategoryDao(db);
    _metas = MetaDao(db);
  }

  ClosetDirs get _d {
    final d = _dirs;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  MediaStore get _m {
    final m = _media;
    if (m == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return m;
  }

  PersonDao get persons {
    final d = _persons;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  ItemDao get items {
    final d = _items;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  ImageDao get images {
    final d = _images;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  BodyDao get bodies {
    final d = _bodies;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  CategoryDao get categories {
    final d = _categories;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  MetaDao get metas {
    final d = _metas;
    if (d == null) throw StateError('数据库尚未初始化，请先 warmUp()');
    return d;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ---- 角色 ----

  @override
  Future<List<Person>> loadPersons() => persons.all();

  @override
  Future<Person> createPerson({required String name, double? heightCm}) =>
      persons.create(name: name, heightCm: heightCm);

  @override
  Future<void> updatePerson(Person person) => persons.update(person);

  @override
  Future<void> deletePerson(String personId) async {
    final files = await persons.deleteWithFiles(personId);
    await _m.deleteAll(files);
  }

  @override
  Future<void> reorderPersons(List<String> idsInOrder) =>
      persons.reorder(idsInOrder);

  @override
  Future<Person> saveAvatar(String personId, Uint8List bytes) async {
    final rel = await _m.saveAvatar(bytes, ext: _extOf(bytes));
    final old = await persons.setAvatar(personId, rel);
    if (old != null) await _m.deleteAll([old]);
    final p = await persons.byId(personId);
    if (p == null) throw StateError('角色不存在：$personId');
    return p;
  }

  @override
  Future<Person> removeAvatar(String personId) async {
    final old = await persons.setAvatar(personId, null);
    if (old != null) await _m.deleteAll([old]);
    final p = await persons.byId(personId);
    if (p == null) throw StateError('角色不存在：$personId');
    return p;
  }

  // ---- 类别 ----

  @override
  Future<List<Category>> loadCategories() => categories.all();

  @override
  Future<Category> createCategory({required String l1, required String name}) =>
      categories.createCustom(l1: l1, name: name);

  @override
  Future<void> renameCategory(String categoryId, String name) =>
      categories.rename(categoryId, name);

  @override
  Future<int> deleteCategory(String categoryId) =>
      categories.deleteCustom(categoryId);

  @override
  Future<int> countItemsInCategory(String categoryId) =>
      categories.countItems(categoryId);

  // ---- 衣服 ----

  @override
  Future<List<Item>> loadItems(
    String personId, {
    ItemStatus? status,
    String? categoryL1,
    String? season,
    String? query,
    SortMode sort = SortMode.newest,
  }) =>
      items.listForPerson(personId,
          status: status,
          categoryL1: categoryL1,
          season: season,
          query: query,
          sort: sort);

  @override
  Future<Map<String, ItemImage>> loadCovers(String personId) =>
      images.coverForPerson(personId);

  @override
  Future<List<ItemImage>> loadImages(String itemId) => images.forItem(itemId);

  @override
  Future<Item> getItem(String itemId) async {
    final item = await items.byId(itemId);
    if (item == null) throw StateError('衣服 $itemId 不存在');
    return item;
  }

  @override
  Future<void> updateItem(Item item) => items.update(item);

  @override
  Future<void> deleteItem(String itemId) async {
    final files = await items.deleteWithFiles(itemId);
    await _m.deleteAll(files);
  }

  @override
  Future<void> confirmAll(String personId) => items.confirmAll(personId);

  @override
  Future<Item> addFlatPhoto({
    required String personId,
    required Uint8List bytes,
    required String name,
    String? categoryL1,
    String? categoryL2,
    List<String> seasons = const [kSeasonAll],
  }) async {
    final origRel = await _m.saveOriginal(bytes, ext: _extOf(bytes));

    // 处理失败不能让录入卡住 —— 保留原图，processed 留空，UI 走降级显示。
    String? procRel;
    String? thumbRel;
    String? colorHex;
    String? colorName;
    try {
      final settings = await _settingsCache();
      final result = await processInIsolate(
        bytes,
        mask: segmenter?.call(bytes),
        tileKey: settings.tileColor,
      );
      procRel = await _m.saveProcessed(result.processed);
      thumbRel = await _m.saveThumb(result.thumb);
      colorHex = result.colorHex;
      colorName = result.colorName;
    } catch (_) {
      procRel = null;
      thumbRel = null;
    }

    final item = await items.create(
      personId: personId,
      name: name,
      categoryL1: categoryL1 ?? 'top',
      categoryL2: categoryL2,
      colorHex: colorHex,
      colorName: colorName,
      seasons: seasons,
      status: ItemStatus.pending,
    );

    await images.add(ItemImage(
      id: _uuid.v4(),
      itemId: item.id,
      kind: ImageKind.flat,
      origPath: origRel,
      processedPath: procRel,
      thumbPath: thumbRel,
      createdAt: nowMs(),
    ));
    return item;
  }

  @override
  Future<Item> replaceFlatPhoto({
    required String itemId,
    required Uint8List bytes,
  }) async {
    final item = await items.byId(itemId);
    if (item == null) throw StateError('衣服 $itemId 不存在');

    final origRel = await _m.saveOriginal(bytes, ext: _extOf(bytes));

    String? procRel;
    String? thumbRel;
    String? colorHex;
    String? colorName;
    try {
      final settings = await _settingsCache();
      final result = await processInIsolate(
        bytes,
        mask: segmenter?.call(bytes),
        tileKey: settings.tileColor,
      );
      procRel = await _m.saveProcessed(result.processed);
      thumbRel = await _m.saveThumb(result.thumb);
      colorHex = result.colorHex;
      colorName = result.colorName;
    } catch (_) {
      procRel = null;
      thumbRel = null;
    }

    // 先记下旧图，插完新的再删 —— 中途失败时至少新图已经落库。
    final oldFlats =
        (await images.forItem(itemId)).where((e) => e.kind == ImageKind.flat);
    final doomed = <String>[];
    for (final f in oldFlats) {
      final files = await images.deleteWithFiles(f.id);
      doomed.addAll(files);
    }

    await images.add(ItemImage(
      id: _uuid.v4(),
      itemId: itemId,
      kind: ImageKind.flat,
      origPath: origRel,
      processedPath: procRel,
      thumbPath: thumbRel,
      createdAt: nowMs(),
    ));

    await _m.deleteAll(doomed);

    // 主色跟着新图走；没提出来就保留原值，别把已有的颜色清空。
    final updated = item.copyWith(
      colorHex: colorHex,
      colorName: colorName,
      updatedAt: nowMs(),
    );
    await items.update(updated);
    return updated;
  }

  @override
  Future<ItemImage> addWornPhoto({
    required String itemId,
    required Uint8List bytes,
    int? wornDate,
  }) async {
    final rel = await _m.saveOriginal(bytes, ext: _extOf(bytes));
    final img = ItemImage(
      id: _uuid.v4(),
      itemId: itemId,
      kind: ImageKind.worn,
      origPath: rel,
      // 上身图按用户要求原样保留，不做任何处理，也不生成缩略图外的东西。
      wornDate: wornDate ?? dayStart(nowMs()),
      createdAt: nowMs(),
    );
    return images.add(img);
  }

  @override
  Future<void> updateImage(ItemImage image) => images.update(image);

  @override
  Future<void> deleteImage(ItemImage image) async {
    final files = await images.deleteWithFiles(image.id);
    await _m.deleteAll(files);
  }

  @override
  Future<Uint8List?> readImageBytes(String? relPath) async {
    if (relPath == null || relPath.isEmpty) return null;
    final file = File(_m.abs(relPath));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  // ---- 身材 ----

  @override
  Future<List<BodyRecord>> loadBodyRecords(String personId) =>
      bodies.forPerson(personId);

  @override
  Future<BodyRecord> saveBodyRecord({
    required String personId,
    required int recordDate,
    required double weightKg,
    required Map<String, double> values,
  }) =>
      bodies.upsert(
        personId: personId,
        recordDate: recordDate,
        weightKg: weightKg,
        values: values,
      );

  @override
  Future<void> deleteBodyRecord(String recordId) => bodies.delete(recordId);

  // ---- 设置 ----

  AppSettings? _settings;

  /// 处理图片时要读底色，而处理是在一次批量录入里循环发生的。
  /// 缓存一份，改设置时清掉，避免每张图都查一次库。
  Future<AppSettings> _settingsCache() async =>
      _settings ??= await metas.readSettings();

  @override
  Future<AppSettings> loadSettings() async {
    _settings = await metas.readSettings();
    return _settings!;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await metas.writeSettings(settings);
    _settings = settings;
  }

  // ---- 备份 ----

  @override
  Future<ExportResult> exportBackup() => ExportService(
        persons: persons,
        items: items,
        images: images,
        bodies: bodies,
        media: _m,
        dirs: _d,
      ).export();

  @override
  Future<BackupPreview> inspectBackup(File file) => ImportService(
        dirs: _d,
        media: _m,
        persons: persons,
        items: items,
        images: images,
        bodies: bodies,
      ).inspect(file);

  @override
  Future<ImportResult> importBackup(File file, ImportMode mode) =>
      ImportService(
        dirs: _d,
        media: _m,
        persons: persons,
        items: items,
        images: images,
        bodies: bodies,
      ).run(file, mode);

  /// 猜扩展名，猜不出按 jpg。只影响落盘文件名，不影响解码。
  String _extOf(Uint8List bytes) {
    if (bytes.length > 12) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[8] == 0x57) {
        return 'webp';
      }
    }
    return 'jpg';
  }
}
