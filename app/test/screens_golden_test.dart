import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingtian_chuanshenme/models.dart';
import 'package:mingtian_chuanshenme/ui/item/capture_page.dart';
import 'package:mingtian_chuanshenme/ui/item/item_detail_page.dart';
import 'package:mingtian_chuanshenme/ui/person/body_record_page.dart';
import 'package:mingtian_chuanshenme/ui/person/body_trend_page.dart';
import 'package:mingtian_chuanshenme/ui/person/person_edit_page.dart';
import 'package:mingtian_chuanshenme/ui/person/person_page.dart';
import 'package:mingtian_chuanshenme/ui/settings/category_page.dart';
import 'package:mingtian_chuanshenme/ui/settings/settings_page.dart';
import 'package:mingtian_chuanshenme/ui/settings/sort_mode_page.dart';
import 'package:mingtian_chuanshenme/ui/settings/tile_color_page.dart';
import 'package:mingtian_chuanshenme/ui/shell/home_shell.dart';
import 'package:mingtian_chuanshenme/ui/wardrobe/pending_queue_page.dart';

import 'support/fake_repository.dart';
import 'support/golden_harness.dart';

/// 全屏截图。跑法：
///   flutter test --update-goldens test/screens_golden_test.dart
/// 产物在 test/goldens/，用 read 工具看。
void main() {
  setUpAll(() async {
    await loadCjkFont();
  });

  late FakeRepository repo;

  setUp(() {
    repo = _seedRepo();
  });

  testWidgets('01 衣橱网格', (tester) async {
    await pumpScreen(tester, const HomeShell(), repo: repo);
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/01_wardrobe.png'),
    );
  });

  testWidgets('02 待确认队列', (tester) async {
    await pumpScreen(tester, const PendingQueuePage(), repo: repo);
    await expectLater(
      find.byType(PendingQueuePage),
      matchesGoldenFile('goldens/02_pending.png'),
    );
  });

  testWidgets('03 衣服详情', (tester) async {
    final item = repo.items.firstWhere((e) => e.name == '灰色卫衣');
    await pumpScreen(tester, ItemDetailPage(itemId: item.id), repo: repo);
    await expectLater(
      find.byType(ItemDetailPage),
      matchesGoldenFile('goldens/03_item_detail.png'),
    );
  });

  testWidgets('04 添加衣服', (tester) async {
    // 从衣橱点「添加衣服」打开弹层，这样截图里带上了遮罩和底下的衣橱，
    // 跟真机上看到的一致；单独把 sheet 摆在一个空 Scaffold 里会是一屏惨白。
    // dpr 用 1.0 让产物也是 390×844，跟其他 10 张对齐。
    await pumpScreen(tester, const HomeShell(), repo: repo, dpr: 1.0);
    await tester.tap(find.text('添加衣服'));
    await tester.pumpAndSettle();
    // 截 MaterialApp 而不是 AddItemSheet：底部弹层的半透明遮罩是独立的
    // route 图层，只截 sheet 自己的子树会把遮罩丢掉，看起来像一屏白。
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/04_add_item.png'),
    );
  });

  testWidgets('05 角色列表', (tester) async {
    await pumpScreen(tester, const PersonListPage(), repo: repo);
    await expectLater(
      find.byType(PersonListPage),
      matchesGoldenFile('goldens/05_persons.png'),
    );
  });

  testWidgets('06 角色主页', (tester) async {
    await pumpScreen(
      tester,
      PersonPage(personId: repo.persons.first.id),
      repo: repo,
    );
    await expectLater(
      find.byType(PersonPage),
      matchesGoldenFile('goldens/06_person_page.png'),
    );
  });

  testWidgets('07 身材记录详情 16 项', (tester) async {
    final pid = repo.persons.first.id;
    final rec = (await repo.loadBodyRecords(pid)).first;
    await pumpScreen(
      tester,
      BodyRecordDetailPage(personId: pid, record: rec),
      repo: repo,
    );
    await expectLater(
      find.byType(BodyRecordDetailPage),
      matchesGoldenFile('goldens/07_body_detail.png'),
    );
  });

  testWidgets('08 记录一次身材', (tester) async {
    await pumpScreen(
      tester,
      // 日期必须固定：这页默认是 DateTime.now()，不固定的话
      // 这份 golden 每天都会挂，而且看起来像真的 UI 改动。
      BodyRecordPage(
        personId: repo.persons.first.id,
        initialDate: DateTime(2026, 11, 3),
      ),
      repo: repo,
    );
    await expectLater(
      find.byType(BodyRecordPage),
      matchesGoldenFile('goldens/08_body_record.png'),
    );
  });

  testWidgets('09 分类体系', (tester) async {
    await pumpScreen(tester, const CategoryPage(), repo: repo);
    // 展开「上装」把自建标签露出来。
    await tester.tap(find.text('上装'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CategoryPage),
      matchesGoldenFile('goldens/09_categories.png'),
    );
  });

  testWidgets('10 添加角色', (tester) async {
    await pumpScreen(tester, const PersonEditPage(), repo: repo);
    await expectLater(
      find.byType(PersonEditPage),
      matchesGoldenFile('goldens/10_person_edit.png'),
    );
  });

  testWidgets('11 我的', (tester) async {
    await pumpScreen(tester, const SettingsPage(), repo: repo);
    await expectLater(
      find.byType(SettingsPage),
      matchesGoldenFile('goldens/11_settings.png'),
    );
  });

  testWidgets('12 角色排序', (tester) async {
    final persons = await repo.loadPersons();
    await pumpScreen(tester, PersonSortPage(persons: persons), repo: repo);
    await expectLater(
      find.byType(PersonSortPage),
      matchesGoldenFile('goldens/12_person_sort.png'),
    );
  });

  testWidgets('13 身材趋势', (tester) async {
    await pumpScreen(
      tester,
      BodyTrendPage(personId: repo.persons.first.id),
      repo: repo,
    );
    await expectLater(
      find.byType(BodyTrendPage),
      matchesGoldenFile('goldens/13_body_trend.png'),
    );
  });

  testWidgets('14 身材趋势·切换指标', (tester) async {
    await pumpScreen(
      tester,
      BodyTrendPage(personId: repo.persons.first.id),
      repo: repo,
    );
    await tester.tap(find.text('腰围'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(BodyTrendPage),
      matchesGoldenFile('goldens/14_body_trend_waist.png'),
    );
  });

  testWidgets('15 连拍（相机不可用时的兜底）', (tester) async {
    // 测试环境里 availableCameras() 抛 MissingPluginException，
    // 正好覆盖「相机打不开」这条分支——真机上没权限也是这条。
    await pumpScreen(tester, const CapturePage(), repo: repo);
    await expectLater(
      find.byType(CapturePage),
      matchesGoldenFile('goldens/15_capture_error.png'),
    );
  });

  testWidgets('16 平铺图底色', (tester) async {
    await pumpScreen(tester, const TileColorPage(), repo: repo);
    await expectLater(
      find.byType(TileColorPage),
      matchesGoldenFile('goldens/16_tile_color.png'),
    );
  });

  testWidgets('17 衣橱排序方式', (tester) async {
    await pumpScreen(tester, const SortModePage(), repo: repo);
    await expectLater(
      find.byType(SortModePage),
      matchesGoldenFile('goldens/17_sort_mode.png'),
    );
  });

  testWidgets('18 衣橱按类别排', (tester) async {
    // 排序存在设置里，改完直接看衣橱的样子——只截排序页看不出效果。
    repo.settings = const AppSettings(sortMode: SortMode.category);
    await pumpScreen(tester, const HomeShell(), repo: repo);
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/18_wardrobe_by_category.png'),
    );
  });

  testWidgets('19 只有上身图的衣服', (tester) async {
    final item = repo.items.firstWhere((e) => e.name == '只有上身图的衬衫');
    await pumpScreen(tester, ItemDetailPage(itemId: item.id), repo: repo);
    await expectLater(
      find.byType(ItemDetailPage),
      matchesGoldenFile('goldens/19_item_worn_only.png'),
    );
  });
}

/// 一份像用了一年的衣橱：两个角色、十几件衣服、几次身材记录。
FakeRepository _seedRepo() {
  final repo = FakeRepository();

  final me = Person(
    id: 'p_me',
    name: '小李',
    heightCm: 168,
    sortIndex: 0,
    createdAt: 1735689600000,
  );
  final them = Person(
    id: 'p_them',
    name: '阿周',
    heightCm: 178,
    sortIndex: 1,
    createdAt: 1735776000000,
  );
  repo.persons.addAll([me, them]);

  // 内置类别（与 db.dart 的种子一致，只取截图要用的部分）。
  repo.categories.addAll(const [
    Category(
        id: 'b_top_0', l1: 'top', name: '短袖T恤', isBuiltin: true, createdAt: 0),
    Category(
        id: 'b_top_1', l1: 'top', name: '长袖T恤', isBuiltin: true, createdAt: 0),
    Category(
        id: 'b_top_2', l1: 'top', name: '衬衫', isBuiltin: true, createdAt: 0),
    Category(
        id: 'b_top_3', l1: 'top', name: '卫衣', isBuiltin: true, createdAt: 0),
    Category(
        id: 'b_top_4', l1: 'top', name: '针织衫', isBuiltin: true, createdAt: 0),
    Category(
        id: 'b_bottom_0',
        l1: 'bottom',
        name: '长裤',
        isBuiltin: true,
        createdAt: 0),
    Category(
        id: 'b_bottom_1',
        l1: 'bottom',
        name: '牛仔裤',
        isBuiltin: true,
        createdAt: 0),
    Category(
        id: 'b_outer_0',
        l1: 'outer',
        name: '夹克',
        isBuiltin: true,
        createdAt: 0),
    Category(
        id: 'b_outer_1',
        l1: 'outer',
        name: '大衣',
        isBuiltin: true,
        createdAt: 0),
    Category(
        id: 'b_shoe_0', l1: 'shoe', name: '运动鞋', isBuiltin: true, createdAt: 0),
    // 两个自建标签
    Category(id: 'c_vest', l1: 'top', name: '背心', sortIndex: 9, createdAt: 0),
    Category(id: 'c_cami', l1: 'top', name: '吊带', sortIndex: 10, createdAt: 0),
  ]);

  final flat1 = 'img/orig/a1.png';
  final flat2 = 'img/orig/a2.png';
  final flat3 = 'img/orig/a3.png';
  final flat4 = 'img/orig/a4.png';
  final flat5 = 'img/orig/a5.png';
  final flat6 = 'img/orig/a6.png';
  final worn1 = 'img/orig/w1.png';

  repo.files.addAll({
    flat1: fakeFlat(shape: GarmentShape.hoodie, paletteIndex: 4),
    flat2: fakeFlat(shape: GarmentShape.tee, paletteIndex: 0),
    flat3: fakeFlat(shape: GarmentShape.pants, paletteIndex: 2),
    flat4: fakeFlat(shape: GarmentShape.coat, paletteIndex: 6),
    flat5: fakeFlat(shape: GarmentShape.tee, paletteIndex: 1, deepTile: true),
    flat6: fakeFlat(shape: GarmentShape.dress, paletteIndex: 5),
    worn1: fakeWorn(seed: 4),
  });

  void add({
    required String id,
    required String personId,
    required String name,
    required String l1,
    String? l2,
    String? colorHex,
    String? colorName,
    List<String> seasons = const [kSeasonAll],
    ItemStatus status = ItemStatus.confirmed,
    double? confidence,
    String? flat,
    String? worn,
    String? wornNote,
    required int createdAt,
  }) {
    repo.items.add(Item(
      id: id,
      personId: personId,
      name: name,
      categoryL1: l1,
      categoryL2: l2,
      colorHex: colorHex,
      colorName: colorName,
      seasons: seasons,
      status: status,
      confidence: confidence,
      createdAt: createdAt,
      updatedAt: createdAt,
    ));
    if (flat != null) {
      repo.images.add(ItemImage(
        id: '${id}_flat',
        itemId: id,
        kind: ImageKind.flat,
        origPath: flat,
        processedPath: flat,
        thumbPath: flat,
        createdAt: createdAt,
      ));
    }
    if (worn != null) {
      repo.images.add(ItemImage(
        id: '${id}_worn',
        itemId: id,
        kind: ImageKind.worn,
        origPath: worn,
        wornDate: 1761955200000,
        note: wornNote,
        createdAt: createdAt,
      ));
    }
  }

  add(
    id: 'it_hoodie',
    personId: 'p_me',
    name: '灰色卫衣',
    l1: 'top',
    l2: 'b_top_3',
    colorHex: '#8A8A8A',
    colorName: '中灰',
    seasons: const ['spring', 'autumn'],
    flat: flat1,
    worn: worn1,
    wornNote: '配牛仔裤穿的',
    createdAt: 1762300800000,
  );
  add(
    id: 'it_blacktee',
    personId: 'p_me',
    name: '黑T恤',
    l1: 'top',
    l2: 'b_top_0',
    colorHex: '#1A1A1A',
    colorName: '黑',
    seasons: const ['summer'],
    flat: flat2,
    createdAt: 1762214400000,
  );
  add(
    id: 'it_jeans',
    personId: 'p_me',
    name: '直筒牛仔裤',
    l1: 'bottom',
    l2: 'b_bottom_1',
    colorHex: '#243352',
    colorName: '藏青',
    seasons: const [kSeasonAll],
    flat: flat3,
    createdAt: 1762128000000,
  );
  add(
    id: 'it_coat',
    personId: 'p_me',
    name: '驼色大衣',
    l1: 'outer',
    l2: 'b_outer_1',
    colorHex: '#C09A6B',
    colorName: '驼',
    seasons: const ['autumn', 'winter'],
    flat: flat4,
    createdAt: 1762041600000,
  );
  add(
    id: 'it_whitetee',
    personId: 'p_me',
    name: '白T恤',
    l1: 'top',
    l2: 'b_top_0',
    colorHex: '#FAFAF7',
    colorName: '白',
    seasons: const ['summer'],
    flat: flat5,
    createdAt: 1761955200000,
  );
  add(
    id: 'it_dress',
    personId: 'p_me',
    name: '酒红长裙',
    l1: 'dress',
    colorHex: '#6E2730',
    colorName: '酒红',
    seasons: const ['spring', 'summer'],
    flat: flat6,
    createdAt: 1761868800000,
  );

  // 待确认三件。名字是自动起的（颜色 + 二级类别），
  // 其中第三件模型拿不准二级类别，只有一个颜色词。
  add(
    id: 'it_p1',
    personId: 'p_me',
    name: '橄榄绿卫衣',
    l1: 'top',
    l2: 'b_top_3',
    colorHex: '#6E743C',
    colorName: '橄榄绿',
    status: ItemStatus.pending,
    confidence: 0.81,
    flat: flat2,
    createdAt: 1762500000000,
  );
  add(
    id: 'it_p2',
    personId: 'p_me',
    name: '米白的衣服',
    l1: 'top',
    l2: null,
    colorHex: '#EFEADF',
    colorName: '米白',
    status: ItemStatus.pending,
    confidence: 0.38,
    flat: flat5,
    createdAt: 1762500060000,
  );
  add(
    id: 'it_p3',
    personId: 'p_me',
    name: '炭灰长裤',
    l1: 'bottom',
    l2: 'b_bottom_0',
    colorHex: '#3A3A3A',
    colorName: '炭灰',
    status: ItemStatus.pending,
    confidence: 0.72,
    flat: flat3,
    createdAt: 1762500120000,
  );

  // 另一个角色的一件，证明衣服不互通。
  add(
    id: 'it_them',
    personId: 'p_them',
    name: '他的黑夹克',
    l1: 'outer',
    l2: 'b_outer_0',
    colorHex: '#1A1A1A',
    colorName: '黑',
    flat: flat4,
    createdAt: 1762300000000,
  );

  // 只有上身图、没有平铺图——详情页要给「补一张」的入口。
  add(
    id: 'it_wornonly',
    personId: 'p_me',
    name: '只有上身图的衬衫',
    l1: 'top',
    l2: 'b_top_2',
    colorHex: '#E8E3D6',
    colorName: '米白',
    seasons: const ['spring', 'summer'],
    worn: worn1,
    wornNote: '第一次试穿',
    createdAt: 1762400000000,
  );

  // 身材记录：最近一次填了 4 项，上一次 3 项。
  repo.seedBodyRecord(
    personId: 'p_me',
    recordDate: DateTime(2026, 10, 28).millisecondsSinceEpoch,
    weightKg: 56.4,
    values: {'waist_cm': 66, 'chest_cm': 84, 'hip_cm': 90, 'thigh_cm': 50},
  );
  repo.seedBodyRecord(
    personId: 'p_me',
    recordDate: DateTime(2026, 9, 12).millisecondsSinceEpoch,
    weightKg: 57.6,
    values: {'waist_cm': 68, 'chest_cm': 85.5, 'hip_cm': 91},
  );
  repo.seedBodyRecord(
    personId: 'p_them',
    recordDate: DateTime(2026, 10, 20).millisecondsSinceEpoch,
    weightKg: 72.0,
    values: {'waist_cm': 80},
  );

  return repo;
}
