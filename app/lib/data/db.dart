import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Schema 版本。字段变更时 +1，并在 [_onUpgrade] 里写迁移。
const kSchemaVersion = 1;

/// 写进备份包 manifest 的版本号，只用于排障，不参与任何判断。
const kAppVersion = '0.2.0';

/// 建表语句与 `设计文档.md` §4.1 的 DDL 逐字对应。
///
/// 与文档的差异只有一处：`person` 表增加了 `height_cm`。
/// 原因是身高只在角色档案里填一次、不在每次记录身材时重复问，
/// 因此它必须存在 person 上；body_record 里冗余的一份用于历史回溯。
const _createPerson = '''
CREATE TABLE person (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  avatar_path   TEXT,
  sort_index    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  height_cm     REAL
)''';

const _createItem = '''
CREATE TABLE item (
  id            TEXT PRIMARY KEY,
  person_id     TEXT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  category_l1   TEXT NOT NULL,
  category_l2   TEXT,
  color_hex     TEXT,
  color_name    TEXT,
  seasons       TEXT,
  status        TEXT NOT NULL DEFAULT 'pending',
  confidence    REAL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
)''';

const _createImage = '''
CREATE TABLE image (
  id             TEXT PRIMARY KEY,
  item_id        TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE,
  kind           TEXT NOT NULL,
  orig_path      TEXT,
  processed_path TEXT,
  thumb_path     TEXT,
  use_processed  INTEGER NOT NULL DEFAULT 1,
  worn_date      INTEGER,
  note           TEXT,
  sort_index     INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL
)''';

const _createBodyRecord = '''
CREATE TABLE body_record (
  id            TEXT PRIMARY KEY,
  person_id     TEXT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  record_date   INTEGER NOT NULL,
  weight_kg     REAL NOT NULL,
  height_cm     REAL,
  chest_cm      REAL,
  underbust_cm  REAL,
  waist_cm      REAL,
  hip_cm        REAL,
  shoulder_cm   REAL,
  back_cm       REAL,
  thigh_cm      REAL,
  calf_cm       REAL,
  arm_cm        REAL,
  neck_cm       REAL,
  arm_len_cm    REAL,
  leg_cm        REAL,
  shoe_size_cn  REAL,
  foot_len_mm   REAL,
  created_at    INTEGER NOT NULL
)''';

const _createCategory = '''
CREATE TABLE category (
  id          TEXT PRIMARY KEY,
  l1          TEXT NOT NULL,
  name        TEXT NOT NULL,
  sort_index  INTEGER NOT NULL DEFAULT 0,
  is_builtin  INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
)''';

const _createMeta = '''
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT
)''';

/// 内置二级类别。id 用固定 code（稳定标识），中文名可改不影响数据。
const kBuiltinCategories = <String, List<String>>{
  'top': ['短袖T恤', '长袖T恤', '衬衫', '卫衣', '针织衫', 'POLO'],
  'bottom': ['长裤', '短裤', '半裙', '牛仔裤', '运动裤'],
  'dress': ['长裙', '短裙'],
  'outer': ['夹克', '大衣', '西装', '羽绒服'],
  'shoe': ['运动鞋', '皮鞋', '靴', '凉鞋'],
  'bag': ['双肩包', '手提包', '斜挎包'],
  'acc': ['帽子', '围巾', '腰带', '首饰'],
};

const kBuiltinCategoryPrefix = 'b_';

Future<Database> openClosetDb(String path) async {
  return openDatabase(
    path,
    version: kSchemaVersion,
    onConfigure: (db) async {
      // 级联删除依赖这个开关，SQLite 默认是关的。
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, version) async {
      await db.execute(_createPerson);
      await db.execute(_createItem);
      await db.execute(_createImage);
      await db.execute(_createBodyRecord);
      await db.execute(_createCategory);
      await db.execute(_createMeta);

      await db
          .execute('CREATE INDEX idx_item_person ON item(person_id, status)');
      await db.execute('CREATE INDEX idx_image_item ON image(item_id, kind)');
      await db.execute(
          'CREATE INDEX idx_body_person ON body_record(person_id, record_date DESC)');
      // 同一天重复记录按 (person_id, record_date) 覆盖，由数据库保证，不依赖业务层。
      await db.execute(
          'CREATE UNIQUE INDEX idx_body_day ON body_record(person_id, record_date)');

      await _seedCategories(db);
    },
    onUpgrade: _onUpgrade,
  );
}

Future<void> _onUpgrade(Database db, int from, int to) async {
  // 第一版尚无历史库。后续字段变更在此追加：
  // if (from < 2) { await db.execute('ALTER TABLE item ADD COLUMN ...'); }
}

Future<void> _seedCategories(Database db) async {
  final batch = db.batch();
  final now = DateTime.now().millisecondsSinceEpoch;
  var i = 0;
  for (final entry in kBuiltinCategories.entries) {
    for (var j = 0; j < entry.value.length; j++) {
      batch.insert('category', {
        'id': '$kBuiltinCategoryPrefix${entry.key}_$j',
        'l1': entry.key,
        'name': entry.value[j],
        'sort_index': j,
        'is_builtin': 1,
        'created_at': now,
      });
      i++;
    }
  }
  await batch.commit(noResult: true);
  assert(i > 0);
}

/// 图片目录布局见设计文档 §6.1。
class ClosetDirs {
  final String root;
  ClosetDirs(this.root);

  String get dbFile => p.join(root, 'closet.db');
  String get orig => p.join(root, 'img', 'orig');
  String get proc => p.join(root, 'img', 'proc');
  String get thumb => p.join(root, 'img', 'thumb');

  /// 角色头像单独一个目录：它和衣服图片的生命周期不同
  /// （删衣服不该碰头像，删角色才一起删），混在 img/orig 里回收时会漏删。
  String get avatar => p.join(root, 'img', 'avatar');
  String get exportDir => p.join(root, 'export');
}

/// 从相对路径还原绝对路径；库里存相对路径，杜绝绝对路径泄漏（见 §6.2）。
String absoluteImagePath(String root, String? rel) {
  if (rel == null) return '';
  return p.join(root, rel);
}
