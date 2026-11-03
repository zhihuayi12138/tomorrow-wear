import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

const _uuid = Uuid();

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 当天 0 点，保证同一天的记录落在同一 record_date 上（配合 idx_body_day 的 UPSERT）。
int dayStart(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

class PersonDao {
  final Database db;
  PersonDao(this.db);

  Future<List<Person>> all() async {
    final rows = await db.query('person', orderBy: 'sort_index ASC, created_at ASC');
    return rows.map(Person.fromMap).toList();
  }

  Future<Person?> byId(String id) async {
    final rows = await db.query('person', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  Future<Person> create({required String name, double? heightCm, String? avatarPath}) async {
    final maxSort = await db.rawQuery('SELECT COALESCE(MAX(sort_index), -1) AS m FROM person');
    final m = (maxSort.first['m'] as int?) ?? -1;
    final person = Person(
      id: _uuid.v4(),
      name: name,
      heightCm: heightCm,
      avatarPath: avatarPath,
      sortIndex: m + 1,
      createdAt: nowMs(),
    );
    await db.insert('person', person.toMap());
    return person;
  }

  Future<void> update(Person p) async {
    await db.update('person', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  /// 导入时按原 id 落库，不重新生成 UUID。
  Future<void> insertRaw(Map<String, Object?> map) async {
    await db.insert('person', map, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 替换式导入用：清空全部角色（衣服与图片靠级联删除）。
  Future<void> deleteAll() async {
    await db.delete('person');
  }

  /// 删角色 → 级联删衣服 → 级联删图片行。**图片文件要业务层物理删除**，
  /// 数据库级联不管文件，见设计文档 §4.1 设计要点。
  Future<List<String>> deleteWithFiles(String personId) async {
    final files = await collectImageFilesForPerson(personId);
    await db.delete('person', where: 'id = ?', whereArgs: [personId]);
    return files;
  }

  Future<List<String>> collectImageFilesForPerson(String personId) async {
    final rows = await db.rawQuery('''
      SELECT i.orig_path, i.processed_path, i.thumb_path
      FROM image i JOIN item it ON it.id = i.item_id
      WHERE it.person_id = ?
    ''', [personId]);
    return _pathsOf(rows);
  }

  Future<void> reorder(List<String> idsInOrder) async {
    final batch = db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('person', {'sort_index': i},
          where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }
}

class ItemDao {
  final Database db;
  ItemDao(this.db);

  Future<List<Item>> listForPerson(
    String personId, {
    ItemStatus? status,
    String? categoryL1,
    String? season,
    String? query,
  }) async {
    final where = <String>['person_id = ?'];
    final args = <Object?>[personId];

    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    if (categoryL1 != null && categoryL1.isNotEmpty) {
      where.add('category_l1 = ?');
      args.add(categoryL1);
    }
    // 季节筛选：四季通用的衣服任何季节都能穿到，所以要一起命中。
    if (season != null && season.isNotEmpty && season != kSeasonAll) {
      where.add("(seasons = ? OR seasons LIKE ? OR seasons LIKE ? OR seasons LIKE ?)");
      args.addAll([
        kSeasonAll,
        '$season,%',
        '%,$season',
        '%,$season,%',
      ]);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%${query.trim()}%');
    }

    final rows = await db.query(
      'item',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Item.fromMap).toList();
  }

  Future<int> countForPerson(String personId, {ItemStatus? status}) async {
    final where = <String>['person_id = ?'];
    final args = <Object?>[personId];
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM item WHERE ${where.join(' AND ')}', args);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<Item?> byId(String id) async {
    final rows = await db.query('item', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Item.fromMap(rows.first);
  }

  Future<Item> create({
    required String personId,
    required String name,
    required String categoryL1,
    String? categoryL2,
    String? colorHex,
    String? colorName,
    List<String> seasons = const [kSeasonAll],
    ItemStatus status = ItemStatus.pending,
    double? confidence,
  }) async {
    final t = nowMs();
    final item = Item(
      id: _uuid.v4(),
      personId: personId,
      name: name,
      categoryL1: categoryL1,
      categoryL2: categoryL2,
      colorHex: colorHex,
      colorName: colorName,
      seasons: seasons,
      status: status,
      confidence: confidence,
      createdAt: t,
      updatedAt: t,
    );
    await db.insert('item', item.toMap());
    return item;
  }

  Future<void> update(Item item) async {
    await db.update('item', item.copyWith(updatedAt: nowMs()).toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  /// 导入时按原 id 落库。
  Future<void> insertRaw(Map<String, Object?> map) async {
    await db.insert('item', map, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> confirmAll(String personId) async {
    await db.update(
      'item',
      {'status': ItemStatus.confirmed.name, 'updated_at': nowMs()},
      where: 'person_id = ? AND status = ?',
      whereArgs: [personId, ItemStatus.pending.name],
    );
  }

  Future<List<String>> deleteWithFiles(String itemId) async {
    final rows = await db.query('image',
        columns: ['orig_path', 'processed_path', 'thumb_path'],
        where: 'item_id = ?',
        whereArgs: [itemId]);
    final files = _pathsOf(rows);
    await db.delete('item', where: 'id = ?', whereArgs: [itemId]);
    return files;
  }
}

class ImageDao {
  final Database db;
  ImageDao(this.db);

  Future<List<ItemImage>> forItem(String itemId) async {
    final rows = await db.query(
      'image',
      where: 'item_id = ?',
      whereArgs: [itemId],
      // 平铺图在前、上身图按日期倒序，见设计文档 P3。
      orderBy: "CASE kind WHEN 'flat' THEN 0 ELSE 1 END, "
          'sort_index ASC, worn_date DESC, created_at ASC',
    );
    return rows.map(ItemImage.fromMap).toList();
  }

  /// 封面图：优先平铺处理版，没有平铺图就退到任意一张缩略图。
  Future<Map<String, ItemImage>> coverForPerson(String personId) async {
    final rows = await db.rawQuery('''
      SELECT i.* FROM image i
      JOIN item it ON it.id = i.item_id
      WHERE it.person_id = ?
      ORDER BY CASE i.kind WHEN 'flat' THEN 0 ELSE 1 END, i.sort_index ASC
    ''', [personId]);
    final map = <String, ItemImage>{};
    for (final r in rows) {
      final img = ItemImage.fromMap(r);
      map.putIfAbsent(img.itemId, () => img);
    }
    return map;
  }

  Future<int> wornCount(String itemId) async {
    final r = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM image WHERE item_id = ? AND kind = 'worn'",
        [itemId]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<ItemImage> add(ItemImage image) async {
    await db.insert('image', image.toMap());
    return image;
  }

  Future<void> update(ItemImage image) async {
    await db.update('image', image.toMap(), where: 'id = ?', whereArgs: [image.id]);
  }

  Future<List<String>> deleteWithFiles(String imageId) async {
    final rows = await db.query('image',
        columns: ['orig_path', 'processed_path', 'thumb_path'],
        where: 'id = ?',
        whereArgs: [imageId]);
    final files = _pathsOf(rows);
    await db.delete('image', where: 'id = ?', whereArgs: [imageId]);
    return files;
  }
}

class BodyDao {
  final Database db;
  BodyDao(this.db);

  Future<List<BodyRecord>> forPerson(String personId) async {
    final rows = await db.query('body_record',
        where: 'person_id = ?',
        whereArgs: [personId],
        orderBy: 'record_date DESC');
    return rows.map(BodyRecord.fromMap).toList();
  }

  Future<BodyRecord?> latest(String personId) async {
    final rows = await db.query('body_record',
        where: 'person_id = ?', whereArgs: [personId], orderBy: 'record_date DESC', limit: 1);
    if (rows.isEmpty) return null;
    return BodyRecord.fromMap(rows.first);
  }

  /// 同一天重复记录走 UPSERT 覆盖，不产生两条。
  /// 冲突键是 (person_id, record_date)，由 idx_body_day 保证。
  Future<BodyRecord> upsert({
    required String personId,
    required int recordDate,
    required double weightKg,
    Map<String, double> values = const {},
  }) async {
    final day = dayStart(recordDate);
    final existing = await db.query('body_record',
        where: 'person_id = ? AND record_date = ?',
        whereArgs: [personId, day],
        limit: 1);

    if (existing.isNotEmpty) {
      final old = BodyRecord.fromMap(existing.first);
      final merged = BodyRecord(
        id: old.id,
        personId: personId,
        recordDate: day,
        weightKg: weightKg,
        // 编辑一次记录时，没填的项保留原值而不是被清空 —— 回填漏项比清空更符合直觉。
        values: {...old.values, ...values},
        createdAt: old.createdAt,
      );
      await db.update('body_record', merged.toMap(),
          where: 'id = ?', whereArgs: [old.id]);
      return merged;
    }

    final rec = BodyRecord(
      id: _uuid.v4(),
      personId: personId,
      recordDate: day,
      weightKg: weightKg,
      values: values,
      createdAt: nowMs(),
    );
    await db.insert('body_record', rec.toMap());
    return rec;
  }

  Future<void> delete(String id) async {
    await db.delete('body_record', where: 'id = ?', whereArgs: [id]);
  }

  /// 导入时按原 id 落库，冲突则跳过（同一天已有记录就保留现有的）。
  Future<void> upsertRaw({
    required String id,
    required String personId,
    required int recordDate,
    required double weightKg,
    required Map<String, double> values,
    required int createdAt,
  }) async {
    final rec = BodyRecord(
      id: id,
      personId: personId,
      recordDate: dayStart(recordDate),
      weightKg: weightKg,
      values: values,
      createdAt: createdAt,
    );
    await db.insert('body_record', rec.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

class CategoryDao {
  final Database db;
  CategoryDao(this.db);

  Future<List<Category>> all() async {
    final rows = await db.query('category', orderBy: 'l1 ASC, sort_index ASC');
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> forL1(String l1) async {
    final rows = await db.query('category',
        where: 'l1 = ?', whereArgs: [l1], orderBy: 'sort_index ASC');
    return rows.map(Category.fromMap).toList();
  }

  Future<Category> createCustom({required String l1, required String name}) async {
    final maxSort = await db.rawQuery(
        'SELECT COALESCE(MAX(sort_index), -1) AS m FROM category WHERE l1 = ?', [l1]);
    final m = (maxSort.first['m'] as int?) ?? -1;
    final c = Category(
      id: _uuid.v4(),
      l1: l1,
      name: name,
      sortIndex: m + 1,
      isBuiltin: false,
      createdAt: nowMs(),
    );
    await db.insert('category', c.toMap());
    return c;
  }

  Future<void> rename(String id, String name) async {
    await db.update('category', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// 删自建类别：**不删衣服**，关联衣服的 category_l2 置空退回一级。
  /// 内置类别只能改名不能删，这里做一次兜底断言。
  Future<int> deleteCustom(String id) async {
    final rows = await db.query('category', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return 0;
    final cat = Category.fromMap(rows.first);
    if (cat.isBuiltin) {
      throw StateError('内置类别只能改名，不能删除');
    }
    final affected = await db.update(
      'item',
      {'category_l2': null, 'updated_at': nowMs()},
      where: 'category_l2 = ?',
      whereArgs: [id],
    );
    await db.delete('category', where: 'id = ?', whereArgs: [id]);
    return affected;
  }

  Future<int> countItems(String categoryL2Id) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM item WHERE category_l2 = ?', [categoryL2Id]);
    return (r.first['c'] as int?) ?? 0;
  }
}

class MetaDao {
  final Database db;
  MetaDao(this.db);

  Future<String?> get(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

List<String> _pathsOf(List<Map<String, Object?>> rows) {
  final out = <String>[];
  for (final r in rows) {
    for (final k in ['orig_path', 'processed_path', 'thumb_path']) {
      final v = r[k] as String?;
      if (v != null && v.isNotEmpty) out.add(v);
    }
  }
  return out;
}
