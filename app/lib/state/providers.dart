import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'repository.dart';

/// 全局唯一的仓储。`main()` 里用 override 换成真实实现，
/// 测试里用 override 换成内存实现 —— 页面代码不需要知道区别。
final repositoryProvider = Provider<ClosetRepository>((ref) {
  throw UnimplementedError('repositoryProvider 必须在 ProviderScope 里 override');
});

/// 启动闸门：建库、建目录、拿初始数据。失败时把错误暴露给 UI，不白屏。
final bootstrapProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(repositoryProvider);
  await repo.warmUp();
  // 模型预热放最后且不等它 —— 冷启动时先让界面出来。
  // 27 MB 模型读进内存要一两秒，挡在启动路径上就是白屏。
  unawaited(repo.prefetchVision());
});

final personsProvider = FutureProvider<List<Person>>((ref) {
  ref.watch(bootstrapProvider);
  return ref.read(repositoryProvider).loadPersons();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(bootstrapProvider);
  return ref.read(repositoryProvider).loadCategories();
});

/// App 级设置（底色、排序）。改完立刻 invalidate 自己，衣橱会重排。
final settingsProvider = FutureProvider<AppSettings>((ref) {
  ref.watch(bootstrapProvider);
  return ref.read(repositoryProvider).loadSettings();
});

/// 当前选中的角色。空衣柜时是 null，UI 负责引导去建角色。
final currentPersonIdProvider = StateProvider<String?>((ref) => null);

/// 实际生效的角色：用户选过的那个若还在就用它，否则退回第一个。
final activePersonProvider = Provider<Person?>((ref) {
  final persons = ref.watch(personsProvider).valueOrNull ?? const <Person>[];
  if (persons.isEmpty) return null;
  final selected = ref.watch(currentPersonIdProvider);
  if (selected != null) {
    for (final p in persons) {
      if (p.id == selected) return p;
    }
  }
  return persons.first;
});

/// 衣橱筛选条件。放在一个不可变对象里，方便 `==` 比较触发重建。
class WardrobeFilter {
  final String? categoryL1;
  final String? season;
  final String query;

  const WardrobeFilter({this.categoryL1, this.season, this.query = ''});

  bool get isEmpty =>
      categoryL1 == null && season == null && query.trim().isEmpty;

  int get activeCount =>
      (categoryL1 == null ? 0 : 1) +
      (season == null ? 0 : 1) +
      (query.trim().isEmpty ? 0 : 1);

  WardrobeFilter copyWith({
    String? categoryL1,
    String? season,
    String? query,
    bool clearCategory = false,
    bool clearSeason = false,
  }) {
    return WardrobeFilter(
      categoryL1: clearCategory ? null : (categoryL1 ?? this.categoryL1),
      season: clearSeason ? null : (season ?? this.season),
      query: query ?? this.query,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WardrobeFilter &&
      other.categoryL1 == categoryL1 &&
      other.season == season &&
      other.query == query;

  @override
  int get hashCode => Object.hash(categoryL1, season, query);
}

final wardrobeFilterProvider =
    StateProvider<WardrobeFilter>((ref) => const WardrobeFilter());

/// 衣橱里的衣服（只含已确认的）。待确认的走 pendingProvider。
final wardrobeItemsProvider = FutureProvider<List<Item>>((ref) async {
  final person = ref.watch(activePersonProvider);
  if (person == null) return const [];
  final filter = ref.watch(wardrobeFilterProvider);
  final sort =
      ref.watch(settingsProvider).valueOrNull?.sortMode ?? SortMode.newest;
  return ref.read(repositoryProvider).loadItems(
        person.id,
        status: ItemStatus.confirmed,
        categoryL1: filter.categoryL1,
        season: filter.season,
        query: filter.query,
        sort: sort,
      );
});

/// 待确认队列：不管筛选条件，永远显示全部待确认项。
final pendingItemsProvider = FutureProvider<List<Item>>((ref) async {
  final person = ref.watch(activePersonProvider);
  if (person == null) return const [];
  return ref
      .read(repositoryProvider)
      .loadItems(person.id, status: ItemStatus.pending);
});

/// 封面图 map，衣橱与待确认共用。
final coversProvider = FutureProvider<Map<String, ItemImage>>((ref) async {
  final person = ref.watch(activePersonProvider);
  if (person == null) return const {};
  return ref.read(repositoryProvider).loadCovers(person.id);
});

/// 详情页的一张衣服。
final itemProvider = FutureProvider.family<Item, String>((ref, itemId) {
  return ref.read(repositoryProvider).getItem(itemId);
});

final itemImagesProvider =
    FutureProvider.family<List<ItemImage>, String>((ref, itemId) {
  return ref.read(repositoryProvider).loadImages(itemId);
});

final bodyRecordsProvider =
    FutureProvider.family<List<BodyRecord>, String>((ref, personId) {
  return ref.read(repositoryProvider).loadBodyRecords(personId);
});

/// 某个一级类别下的二级类别，按一级 code 分组。
final categoriesByL1Provider = Provider<Map<String, List<Category>>>((ref) {
  final all = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
  final map = <String, List<Category>>{};
  for (final c in all) {
    map.putIfAbsent(c.l1, () => []).add(c);
  }
  return map;
});

/// 让所有列表类 provider 一起失效。任何写操作之后调它，
/// 比在几十个地方手写 invalidate 更不容易漏。
void refreshLists(WidgetRef ref) {
  ref.invalidate(wardrobeItemsProvider);
  ref.invalidate(pendingItemsProvider);
  ref.invalidate(coversProvider);
  ref.invalidate(categoriesProvider);
}

/// 读一张图给 Image.memory 用。返回 null 表示文件不存在（例如导入时缺图）。
final imageBytesProvider =
    FutureProvider.family<Uint8List?, String>((ref, relPath) async {
  if (relPath.isEmpty) return null;
  return ref.read(repositoryProvider).readImageBytes(relPath);
});

/// 角色数、衣服数之类的小统计，给「我的」页用。
final statsProvider =
    FutureProvider<({int persons, int items, int images})>((ref) async {
  ref.watch(personsProvider);
  final persons = ref.watch(personsProvider).valueOrNull ?? const <Person>[];
  final repo = ref.read(repositoryProvider);
  var items = 0;
  var images = 0;
  for (final p in persons) {
    final all = await repo.loadItems(p.id);
    items += all.length;
    for (final it in all) {
      images += (await repo.loadImages(it.id)).length;
    }
  }
  return (persons: persons.length, items: items, images: images);
});

/// 备份用的文件选择结果占位；真正的选择在 UI 层做。
class PickedBackup {
  final File file;
  const PickedBackup(this.file);
}
