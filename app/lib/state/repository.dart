import 'dart:io';
import 'dart:typed_data';

import '../core/backup.dart';
import '../models.dart';

/// UI 只依赖这个接口，不直接碰 sqflite / 文件系统。
///
/// 好处是 golden 测试里可以整个换成内存实现，
/// 页面代码一行都不用改，也不会为了测试在控件里塞 if。
abstract class ClosetRepository {
  /// 建目录、打开数据库、写种子数据。App 启动时调一次。
  Future<void> warmUp();

  // ---- 角色 ----
  Future<List<Person>> loadPersons();
  Future<Person> createPerson({required String name, double? heightCm});
  Future<void> updatePerson(Person person);
  Future<void> deletePerson(String personId);

  /// 按给定顺序重排角色，下标即新的 sortIndex。
  Future<void> reorderPersons(List<String> idsInOrder);

  /// 存一张头像，返回更新后的角色。
  Future<Person> saveAvatar(String personId, Uint8List bytes);

  /// 清掉头像，回到名字首字。
  Future<Person> removeAvatar(String personId);

  // ---- 二级类别 ----
  Future<List<Category>> loadCategories();
  Future<Category> createCategory({required String l1, required String name});
  Future<void> renameCategory(String categoryId, String name);

  /// 返回受影响的衣服数量（这些衣服的二级类别会被置空）。
  Future<int> deleteCategory(String categoryId);

  Future<int> countItemsInCategory(String categoryId);

  // ---- 衣服 ----
  Future<List<Item>> loadItems(
    String personId, {
    ItemStatus? status,
    String? categoryL1,
    String? season,
    String? query,
  });

  /// itemId → 封面图。
  Future<Map<String, ItemImage>> loadCovers(String personId);

  Future<List<ItemImage>> loadImages(String itemId);
  Future<Item> getItem(String itemId);
  Future<void> updateItem(Item item);
  Future<void> deleteItem(String itemId);
  Future<void> confirmAll(String personId);

  /// 录入一张平铺图：自动处理 + 建档，状态为 pending。
  Future<Item> addFlatPhoto({
    required String personId,
    required Uint8List bytes,
    required String name,
    String? categoryL1,
    String? categoryL2,
    List<String> seasons,
  });

  Future<ItemImage> addWornPhoto({
    required String itemId,
    required Uint8List bytes,
    int? wornDate,
  });

  Future<void> updateImage(ItemImage image);
  Future<void> deleteImage(ItemImage image);

  /// 直接读一张图给预览用（详情页原图/处理图切换）。
  Future<Uint8List?> readImageBytes(String? relPath);

  // ---- 身材 ----
  Future<List<BodyRecord>> loadBodyRecords(String personId);
  Future<BodyRecord> saveBodyRecord({
    required String personId,
    required int recordDate,
    required double weightKg,
    required Map<String, double> values,
  });
  Future<void> deleteBodyRecord(String recordId);

  // ---- 备份 ----
  Future<ExportResult> exportBackup();
  Future<BackupPreview> inspectBackup(File file);
  Future<ImportResult> importBackup(File file, ImportMode mode);
}
