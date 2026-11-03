import 'dart:io';
import 'dart:typed_data';

import 'package:mingtian_chuanshenme/core/backup.dart';
import 'package:mingtian_chuanshenme/models.dart';
import 'package:mingtian_chuanshenme/state/repository.dart';

/// 内存实现，专供 golden / widget 测试。
///
/// 不用 sqflite 是因为测试里跑真实数据库会让 golden 结果依赖插件，
/// 而且慢。页面只依赖 [ClosetRepository]，所以替换是干净的。
class FakeRepository implements ClosetRepository {
  final List<Person> persons = [];
  final List<Item> items = [];
  final List<ItemImage> images = [];
  final List<BodyRecord> bodyRecords = [];
  final List<Category> categories = [];

  /// relPath → 图片字节。没有的路径会当成「文件缺失」，用于测降级显示。
  final Map<String, Uint8List> files = {};

  int _seq = 0;
  String _id(String prefix) => '$prefix${++_seq}';

  @override
  Future<void> warmUp() async {}

  // ---- 角色 ----

  @override
  Future<List<Person>> loadPersons() async =>
      [...persons]..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  @override
  Future<Person> createPerson({required String name, double? heightCm}) async {
    final p = Person(
      id: _id('p'),
      name: name,
      heightCm: heightCm,
      sortIndex: persons.length,
      createdAt: 1767225600000,
    );
    persons.add(p);
    return p;
  }

  @override
  Future<void> updatePerson(Person person) async {
    final i = persons.indexWhere((e) => e.id == person.id);
    if (i >= 0) persons[i] = person;
  }

  @override
  Future<void> deletePerson(String personId) async {
    persons.removeWhere((e) => e.id == personId);
    final gone =
        items.where((e) => e.personId == personId).map((e) => e.id).toSet();
    items.removeWhere((e) => e.personId == personId);
    images.removeWhere((e) => gone.contains(e.itemId));
    bodyRecords.removeWhere((e) => e.personId == personId);
  }

  @override
  Future<Person> saveAvatar(String personId, Uint8List bytes) async {
    final i = persons.indexWhere((e) => e.id == personId);
    if (i < 0) throw StateError('角色不存在：$personId');
    final rel = 'img/avatar/${_id('av')}.png';
    files[rel] = bytes;
    final old = persons[i].avatarPath;
    if (old != null) files.remove(old);
    persons[i] = persons[i].copyWith(avatarPath: rel);
    return persons[i];
  }

  @override
  Future<Person> removeAvatar(String personId) async {
    final i = persons.indexWhere((e) => e.id == personId);
    if (i < 0) throw StateError('角色不存在：$personId');
    final old = persons[i].avatarPath;
    if (old != null) files.remove(old);
    persons[i] = persons[i].copyWith(clearAvatar: true);
    return persons[i];
  }

  @override
  Future<void> reorderPersons(List<String> idsInOrder) async {
    for (var i = 0; i < idsInOrder.length; i++) {
      final k = persons.indexWhere((e) => e.id == idsInOrder[i]);
      if (k >= 0) persons[k] = persons[k].copyWith(sortIndex: i);
    }
  }

  // ---- 类别 ----

  @override
  Future<List<Category>> loadCategories() async => [...categories];

  @override
  Future<Category> createCategory({
    required String l1,
    required String name,
  }) async {
    final c = Category(
      id: _id('c'),
      l1: l1,
      name: name,
      sortIndex: categories.length,
      createdAt: 1767225600000,
    );
    categories.add(c);
    return c;
  }

  @override
  Future<void> renameCategory(String categoryId, String name) async {
    final i = categories.indexWhere((e) => e.id == categoryId);
    if (i >= 0) {
      final old = categories[i];
      categories[i] = Category(
        id: old.id,
        l1: old.l1,
        name: name,
        sortIndex: old.sortIndex,
        isBuiltin: old.isBuiltin,
        createdAt: old.createdAt,
      );
    }
  }

  @override
  Future<int> deleteCategory(String categoryId) async {
    categories.removeWhere((e) => e.id == categoryId);
    var n = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].categoryL2 == categoryId) {
        items[i] = items[i].copyWith(clearCategoryL2: true);
        n++;
      }
    }
    return n;
  }

  @override
  Future<int> countItemsInCategory(String categoryId) async =>
      items.where((e) => e.categoryL2 == categoryId).length;

  // ---- 衣服 ----

  @override
  Future<List<Item>> loadItems(
    String personId, {
    ItemStatus? status,
    String? categoryL1,
    String? season,
    String? query,
  }) async {
    return items.where((e) {
      if (e.personId != personId) return false;
      if (status != null && e.status != status) return false;
      if (categoryL1 != null && e.categoryL1 != categoryL1) return false;
      if (season != null &&
          season != kSeasonAll &&
          !e.seasons.contains(season) &&
          !e.seasons.contains(kSeasonAll)) {
        return false;
      }
      if (query != null &&
          query.trim().isNotEmpty &&
          !e.name.contains(query.trim())) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Map<String, ItemImage>> loadCovers(String personId) async {
    final ids =
        items.where((e) => e.personId == personId).map((e) => e.id).toSet();
    final map = <String, ItemImage>{};
    for (final im in images) {
      if (!ids.contains(im.itemId)) continue;
      final existing = map[im.itemId];
      if (existing == null ||
          (im.kind == ImageKind.flat && existing.kind != ImageKind.flat)) {
        map[im.itemId] = im;
      }
    }
    return map;
  }

  @override
  Future<List<ItemImage>> loadImages(String itemId) async {
    return images.where((e) => e.itemId == itemId).toList()
      ..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : a.sortIndex.compareTo(b.sortIndex);
      });
  }

  @override
  Future<Item> getItem(String itemId) async =>
      items.firstWhere((e) => e.id == itemId);

  @override
  Future<void> updateItem(Item item) async {
    final i = items.indexWhere((e) => e.id == item.id);
    if (i >= 0) items[i] = item;
  }

  @override
  Future<void> deleteItem(String itemId) async {
    items.removeWhere((e) => e.id == itemId);
    images.removeWhere((e) => e.itemId == itemId);
  }

  @override
  Future<void> confirmAll(String personId) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].personId == personId &&
          items[i].status == ItemStatus.pending) {
        items[i] = items[i].copyWith(status: ItemStatus.confirmed);
      }
    }
  }

  @override
  Future<Item> addFlatPhoto({
    required String personId,
    required Uint8List bytes,
    required String name,
    String? categoryL1,
    String? categoryL2,
    List<String> seasons = const [kSeasonAll],
  }) async {
    final item = await newItem(
      personId: personId,
      name: name,
      categoryL1: categoryL1 ?? 'top',
      categoryL2: categoryL2,
      seasons: seasons,
    );
    final origRel = 'img/orig/flat$_seq.jpg';
    files[origRel] = bytes;
    images.add(ItemImage(
      id: _id('i'),
      itemId: item.id,
      kind: ImageKind.flat,
      origPath: origRel,
      processedPath: origRel,
      thumbPath: origRel,
      createdAt: 1767225600000,
    ));
    return item;
  }

  /// 测试直接造数据用，绕过 UI。
  Future<Item> newItem({
    required String personId,
    required String name,
    String categoryL1 = 'top',
    String? categoryL2,
    List<String> seasons = const [kSeasonAll],
    ItemStatus status = ItemStatus.pending,
    double? confidence,
    String? colorHex,
    String? colorName,
  }) async {
    final item = Item(
      id: _id('it'),
      personId: personId,
      name: name,
      categoryL1: categoryL1,
      categoryL2: categoryL2,
      seasons: seasons,
      status: status,
      confidence: confidence,
      colorHex: colorHex,
      colorName: colorName,
      createdAt: 1767225600000 + _seq,
      updatedAt: 1767225600000 + _seq,
    );
    items.add(item);
    return item;
  }

  /// 测试直接造数据用，绕过 UI。
  Future<Item> seedItem({
    required String personId,
    required String name,
    String categoryL1 = 'top',
    String? categoryL2,
    List<String> seasons = const [kSeasonAll],
    ItemStatus status = ItemStatus.confirmed,
    double? confidence,
    String? colorHex,
    String? colorName,
    String? flatPath,
    bool withWorn = false,
    String? wornPath,
  }) async {
    final item = await newItem(
      personId: personId,
      name: name,
      categoryL1: categoryL1,
      categoryL2: categoryL2,
      seasons: seasons,
      status: status,
      confidence: confidence,
      colorHex: colorHex,
      colorName: colorName,
    );
    if (flatPath != null) {
      images.add(ItemImage(
        id: _id('i'),
        itemId: item.id,
        kind: ImageKind.flat,
        origPath: flatPath,
        processedPath: flatPath,
        thumbPath: flatPath,
        createdAt: item.createdAt,
      ));
    }
    if (withWorn) {
      images.add(ItemImage(
        id: _id('i'),
        itemId: item.id,
        kind: ImageKind.worn,
        origPath: wornPath,
        wornDate: 1767225600000,
        createdAt: item.createdAt,
      ));
    }
    return item;
  }

  @override
  Future<ItemImage> addWornPhoto({
    required String itemId,
    required Uint8List bytes,
    int? wornDate,
  }) async {
    final rel = 'img/orig/worn$_seq.jpg';
    files[rel] = bytes;
    final im = ItemImage(
      id: _id('i'),
      itemId: itemId,
      kind: ImageKind.worn,
      origPath: rel,
      wornDate: wornDate ?? 1767225600000,
      createdAt: 1767225600000,
    );
    images.add(im);
    return im;
  }

  @override
  Future<void> updateImage(ItemImage image) async {
    final i = images.indexWhere((e) => e.id == image.id);
    if (i >= 0) images[i] = image;
  }

  @override
  Future<void> deleteImage(ItemImage image) async {
    images.removeWhere((e) => e.id == image.id);
  }

  @override
  Future<Uint8List?> readImageBytes(String? relPath) async {
    if (relPath == null) return null;
    return files[relPath];
  }

  // ---- 身材 ----

  @override
  Future<List<BodyRecord>> loadBodyRecords(String personId) async {
    return bodyRecords.where((e) => e.personId == personId).toList()
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));
  }

  @override
  Future<BodyRecord> saveBodyRecord({
    required String personId,
    required int recordDate,
    required double weightKg,
    required Map<String, double> values,
  }) async {
    final day = DateTime.fromMillisecondsSinceEpoch(recordDate);
    final normalized =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final i = bodyRecords.indexWhere(
        (e) => e.personId == personId && e.recordDate == normalized);
    if (i >= 0) {
      final old = bodyRecords[i];
      final merged = BodyRecord(
        id: old.id,
        personId: personId,
        recordDate: normalized,
        weightKg: weightKg,
        values: {...old.values, ...values},
        createdAt: old.createdAt,
      );
      bodyRecords[i] = merged;
      return merged;
    }
    final rec = BodyRecord(
      id: _id('b'),
      personId: personId,
      recordDate: normalized,
      weightKg: weightKg,
      values: values,
      createdAt: 1767225600000,
    );
    bodyRecords.add(rec);
    return rec;
  }

  /// 测试直接造数据用，绕过 UI。
  void seedBodyRecord({
    required String personId,
    required int recordDate,
    required double weightKg,
    Map<String, double> values = const {},
  }) {
    bodyRecords.add(BodyRecord(
      id: _id('b'),
      personId: personId,
      recordDate: recordDate,
      weightKg: weightKg,
      values: values,
      createdAt: recordDate,
    ));
  }

  @override
  Future<void> deleteBodyRecord(String recordId) async {
    bodyRecords.removeWhere((e) => e.id == recordId);
  }

  // ---- 备份 ----

  @override
  Future<ExportResult> exportBackup() async =>
      throw UnimplementedError('golden 测试里不做导出');

  @override
  Future<BackupPreview> inspectBackup(File file) async =>
      throw UnimplementedError('golden 测试里不做导入');

  @override
  Future<ImportResult> importBackup(File file, ImportMode mode) async =>
      throw UnimplementedError('golden 测试里不做导入');
}
