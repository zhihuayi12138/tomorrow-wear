import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mingtian_chuanshenme/models.dart';
import 'package:mingtian_chuanshenme/state/sqlite_repository.dart';

/// 真机上走一遍**完整录入链路**：仓储 + 真数据库 + 真文件 + 真模型。
///
/// 为什么单独开这个文件：原来只有 `vision_device_test.dart`，它直接调
/// `ClosetVision.analyze()`，压根没经过 `SqliteRepository.addFlatPhoto`。
/// 用户点「加入待确认」闪退，正好落在这中间没人验过的那一段
/// （sqflite 事务、文件落盘、Isolate）。
///
///   flutter test integration_test/ingest_device_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SqliteRepository repo;

  setUpAll(() async {
    repo = SqliteRepository();
    await repo.warmUp();
  });

  tearDownAll(() async {
    await repo.close();
  });

  Future<Uint8List> sample(String name) async {
    final d = await rootBundle.load('integration_test/samples/$name');
    return d.buffer.asUint8List();
  }

  testWidgets('新库能建起来，内置类别也在', (tester) async {
    final cats = await repo.loadCategories();
    expect(cats, isNotEmpty, reason: '内置类别没种进去，分类结果会落到空 id 上');
    debugPrint('类别 ${cats.length} 个，前三个：'
        '${cats.take(3).map((c) => "${c.l1}/${c.name}").join(", ")}');
  });

  testWidgets('addFlatPhoto 真机全链路不崩，且能读回', (tester) async {
    final person = await repo.createPerson(name: '测试角色', heightCm: 168);
    final bytes = await sample('tshirt_0.jpg');

    // 这一行就是用户点「加入待确认」时执行的东西。
    final item = await repo.addFlatPhoto(personId: person.id, bytes: bytes);

    debugPrint('录入了：name=${item.name} l1=${item.categoryL1} '
        'l2=${item.categoryL2} color=${item.colorName} '
        'confidence=${item.confidence}');

    expect(item.status, ItemStatus.pending);
    expect(item.categoryL1, isIn(L1Category.all.map((c) => c.code)));

    // 二级类别必须真的在库里 —— 拼错 id 不会崩，只会显示成空白。
    if (item.categoryL2 != null) {
      final cats = await repo.loadCategories();
      final hit = cats.where((c) => c.id == item.categoryL2);
      expect(hit, isNotEmpty,
          reason: '二级类别 id ${item.categoryL2} 在库里不存在，界面会显示空白');
    }

    final images = await repo.loadImages(item.id);
    expect(images, isNotEmpty);
    final flat = images.firstWhere((i) => i.kind == ImageKind.flat);
    expect(flat.origPath, isNotNull);

    // 图片文件要真的能读出来，否则网格上是一片占位符。
    final raw = await repo.readImageBytes(flat.gridPath);
    expect(raw, isNotNull, reason: '缩略图读不出来');
    expect(raw!.length, greaterThan(0));

    // 处理图是抠图后才有的；没有也合法（面积兜底会退回原图）。
    if (flat.processedPath != null) {
      final proc = await repo.readImageBytes(flat.processedPath);
      expect(proc, isNotNull);
      debugPrint('抠图版 ${proc!.length} 字节，原图 ${raw.length} 字节');
    } else {
      debugPrint('这张没出处理图（抠图判失败，退回原图）');
    }
  });

  testWidgets('连着录三张不崩，且各自的类别不串', (tester) async {
    final persons = await repo.loadPersons();
    final person = persons.isEmpty
        ? await repo.createPerson(name: '测试角色2')
        : persons.first;

    const names = ['sneaker_0.jpg', 'hat_0.jpg', 'backpack_0.jpg'];
    const expectL1 = ['shoe', 'acc', 'bag'];

    for (var i = 0; i < names.length; i++) {
      final bytes = await sample(names[i]);
      final item = await repo.addFlatPhoto(personId: person.id, bytes: bytes);
      debugPrint('${names[i]} -> ${item.categoryL1} / ${item.categoryL2} '
          '「${item.name}」');
      expect(item.categoryL1, expectL1[i],
          reason: '${names[i]} 类别串了：实得 ${item.categoryL1}');
    }

    final pending = await repo.loadItems(person.id, status: ItemStatus.pending);
    expect(pending.length, greaterThanOrEqualTo(3));
  });

  testWidgets('待确认能批量确认，进衣橱网格', (tester) async {
    final persons = await repo.loadPersons();
    final person = persons.first;

    await repo.confirmAll(person.id);
    final confirmed =
        await repo.loadItems(person.id, status: ItemStatus.confirmed);
    final pending = await repo.loadItems(person.id, status: ItemStatus.pending);
    expect(pending, isEmpty);
    expect(confirmed, isNotEmpty);

    // 网格靠 covers 拿封面，这一步挂了会看到一片空白格。
    final covers = await repo.loadCovers(person.id);
    expect(covers, isNotEmpty, reason: '封面为空，衣橱网格会是空的');
    debugPrint('确认 ${confirmed.length} 件，封面 ${covers.length} 张');
  });
}
