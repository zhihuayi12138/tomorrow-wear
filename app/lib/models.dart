/// 领域模型。
///
/// 编号约定：id 一律 UUID v4（导出/导入/合并不撞号）。
/// 时间一律 epoch ms（INTEGER），不存时区字符串。
library;

class Person {
  final String id;
  final String name;
  final String? avatarPath;
  final int sortIndex;
  final int createdAt;

  /// 身高只在角色档案里填一次，记录身材时不再重复问。
  final double? heightCm;

  const Person({
    required this.id,
    required this.name,
    this.avatarPath,
    this.sortIndex = 0,
    required this.createdAt,
    this.heightCm,
  });

  Person copyWith({
    String? name,
    String? avatarPath,
    int? sortIndex,
    double? heightCm,
    bool clearAvatar = false,
    bool clearHeight = false,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt,
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'avatar_path': avatarPath,
        'sort_index': sortIndex,
        'created_at': createdAt,
        'height_cm': heightCm,
      };

  factory Person.fromMap(Map<String, Object?> m) => Person(
        id: m['id'] as String,
        name: m['name'] as String,
        avatarPath: m['avatar_path'] as String?,
        sortIndex: (m['sort_index'] as int?) ?? 0,
        createdAt: (m['created_at'] as int?) ?? 0,
        heightCm: (m['height_cm'] as num?)?.toDouble(),
      );
}

enum ItemStatus { pending, confirmed }

class Item {
  final String id;
  final String personId;
  final String name;
  final String categoryL1;
  final String? categoryL2;
  final String? colorHex;
  final String? colorName;
  final List<String> seasons;
  final ItemStatus status;

  /// 分类置信度，低于 0.45 时队列里高亮「请确认类别」。
  final double? confidence;

  final int createdAt;
  final int updatedAt;

  const Item({
    required this.id,
    required this.personId,
    required this.name,
    required this.categoryL1,
    this.categoryL2,
    this.colorHex,
    this.colorName,
    this.seasons = const ['all'],
    this.status = ItemStatus.pending,
    this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  Item copyWith({
    String? name,
    String? categoryL1,
    String? categoryL2,
    String? colorHex,
    String? colorName,
    List<String>? seasons,
    ItemStatus? status,
    double? confidence,
    int? updatedAt,
    bool clearCategoryL2 = false,
  }) {
    return Item(
      id: id,
      personId: personId,
      name: name ?? this.name,
      categoryL1: categoryL1 ?? this.categoryL1,
      categoryL2: clearCategoryL2 ? null : (categoryL2 ?? this.categoryL2),
      colorHex: colorHex ?? this.colorHex,
      colorName: colorName ?? this.colorName,
      seasons: seasons ?? this.seasons,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'name': name,
        'category_l1': categoryL1,
        'category_l2': categoryL2,
        'color_hex': colorHex,
        'color_name': colorName,
        'seasons': seasons.join(','),
        'status': status.name,
        'confidence': confidence,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        personId: m['person_id'] as String,
        name: m['name'] as String,
        categoryL1: m['category_l1'] as String,
        categoryL2: m['category_l2'] as String?,
        colorHex: m['color_hex'] as String?,
        colorName: m['color_name'] as String?,
        seasons: _splitSeasons(m['seasons'] as String?),
        status: (m['status'] as String?) == 'pending'
            ? ItemStatus.pending
            : ItemStatus.confirmed,
        confidence: (m['confidence'] as num?)?.toDouble(),
        createdAt: (m['created_at'] as int?) ?? 0,
        updatedAt: (m['updated_at'] as int?) ?? 0,
      );

  static List<String> _splitSeasons(String? s) {
    if (s == null || s.isEmpty) return const ['all'];
    return s.split(',').where((e) => e.isNotEmpty).toList();
  }
}

enum ImageKind { flat, worn }

class ItemImage {
  final String id;
  final String itemId;
  final ImageKind kind;

  /// 原图相对路径。平铺图的原图永不覆盖，见设计文档 5.2。
  final String? origPath;

  /// 抠图/换底后相对路径，仅 flat 有值。
  final String? processedPath;
  final String? thumbPath;

  /// 1=详情页用处理版，0=用原图。用户对失败案例的手动出口。
  final bool useProcessed;

  /// 仅 worn：穿着日期。
  final int? wornDate;
  final String? note;
  final int sortIndex;
  final int createdAt;

  const ItemImage({
    required this.id,
    required this.itemId,
    required this.kind,
    this.origPath,
    this.processedPath,
    this.thumbPath,
    this.useProcessed = true,
    this.wornDate,
    this.note,
    this.sortIndex = 0,
    required this.createdAt,
  });

  /// 详情页实际展示的图：优先处理版。
  String? get displayPath {
    if (kind == ImageKind.flat && useProcessed) {
      return processedPath ?? origPath;
    }
    return origPath ?? processedPath;
  }

  /// 网格只加载缩略图，禁止加载原图，见设计文档 7 性能约束。
  String? get gridPath => thumbPath ?? displayPath;

  ItemImage copyWith({
    String? origPath,
    String? processedPath,
    String? thumbPath,
    bool? useProcessed,
    int? wornDate,
    String? note,
    int? sortIndex,
  }) {
    return ItemImage(
      id: id,
      itemId: itemId,
      kind: kind,
      origPath: origPath ?? this.origPath,
      processedPath: processedPath ?? this.processedPath,
      thumbPath: thumbPath ?? this.thumbPath,
      useProcessed: useProcessed ?? this.useProcessed,
      wornDate: wornDate ?? this.wornDate,
      note: note ?? this.note,
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'item_id': itemId,
        'kind': kind.name,
        'orig_path': origPath,
        'processed_path': processedPath,
        'thumb_path': thumbPath,
        'use_processed': useProcessed ? 1 : 0,
        'worn_date': wornDate,
        'note': note,
        'sort_index': sortIndex,
        'created_at': createdAt,
      };

  factory ItemImage.fromMap(Map<String, Object?> m) => ItemImage(
        id: m['id'] as String,
        itemId: m['item_id'] as String,
        kind: (m['kind'] as String?) == 'worn' ? ImageKind.worn : ImageKind.flat,
        origPath: m['orig_path'] as String?,
        processedPath: m['processed_path'] as String?,
        thumbPath: m['thumb_path'] as String?,
        useProcessed: (m['use_processed'] as int?) != 0,
        wornDate: m['worn_date'] as int?,
        note: m['note'] as String?,
        sortIndex: (m['sort_index'] as int?) ?? 0,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// 身体数据字段定义。
///
/// 顺序即「人怎么量」的顺序（躯干→四肢→脚），不是字典序。见设计文档 P12。
class BodyField {
  final String key;
  final String label;
  final String group;
  final String unit;

  /// 组标题右侧写的用途说明 —— 让人知道量了不白量。
  const BodyField(this.key, this.label, this.group, {this.unit = 'cm'});

  static const all = <BodyField>[
    BodyField('chest_cm', '胸围', '躯干'),
    BodyField('underbust_cm', '下胸围', '躯干'),
    BodyField('waist_cm', '腰围', '躯干'),
    BodyField('hip_cm', '臀围', '躯干'),
    BodyField('shoulder_cm', '肩宽', '躯干'),
    BodyField('back_cm', '背长', '躯干'),
    BodyField('thigh_cm', '大腿围', '四肢'),
    BodyField('calf_cm', '小腿围', '四肢'),
    BodyField('arm_cm', '臂围', '四肢'),
    BodyField('neck_cm', '颈围', '四肢'),
    BodyField('arm_len_cm', '臂长', '四肢'),
    BodyField('leg_cm', '腿长', '四肢'),
    BodyField('shoe_size_cn', '鞋码', '脚', unit: '码'),
    BodyField('foot_len_mm', '脚长', '脚', unit: 'mm'),
  ];

  static List<String> groupsInOrder() {
    final seen = <String>[];
    for (final f in all) {
      if (!seen.contains(f.group)) seen.add(f.group);
    }
    return seen;
  }
}

/// 身材记录。除日期与体重外全部可空（选填）。
class BodyRecord {
  final String id;
  final String personId;
  final int recordDate; // 当天 0 点
  final double weightKg;
  final Map<String, double> values; // key 见 BodyField.key
  final int createdAt;

  const BodyRecord({
    required this.id,
    required this.personId,
    required this.recordDate,
    required this.weightKg,
    this.values = const {},
    required this.createdAt,
  });

  double? operator [](String key) => values[key];

  Map<String, Object?> toMap() {
    final m = <String, Object?>{
      'id': id,
      'person_id': personId,
      'record_date': recordDate,
      'weight_kg': weightKg,
      'created_at': createdAt,
    };
    for (final f in BodyField.all) {
      m[f.key] = values[f.key];
    }
    return m;
  }

  factory BodyRecord.fromMap(Map<String, Object?> m) {
    final vals = <String, double>{};
    for (final f in BodyField.all) {
      final v = m[f.key];
      if (v != null) vals[f.key] = (v as num).toDouble();
    }
    return BodyRecord(
      id: m['id'] as String,
      personId: m['person_id'] as String,
      recordDate: (m['record_date'] as int?) ?? 0,
      weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
      values: vals,
      createdAt: (m['created_at'] as int?) ?? 0,
    );
  }

  /// 这一条填了几项（不含身高，身高在角色档案里）。
  int get filledCount => values.length;
}

/// 二级类别。一级写死在代码里，二级可自建。
class Category {
  final String id;
  final String l1;
  final String name;
  final int sortIndex;

  /// 1=内置，只能改名不能删；0=自建，可改名可删。
  final bool isBuiltin;
  final int createdAt;

  const Category({
    required this.id,
    required this.l1,
    required this.name,
    this.sortIndex = 0,
    this.isBuiltin = false,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'l1': l1,
        'name': name,
        'sort_index': sortIndex,
        'is_builtin': isBuiltin ? 1 : 0,
        'created_at': createdAt,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        l1: m['l1'] as String,
        name: m['name'] as String,
        sortIndex: (m['sort_index'] as int?) ?? 0,
        isBuiltin: (m['is_builtin'] as int?) == 1,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// 一级类别写死在代码里（导出按 code 存，保证跨版本兼容）。
class L1Category {
  final String code;
  final String label;
  const L1Category(this.code, this.label);

  static const all = <L1Category>[
    L1Category('top', '上装'),
    L1Category('bottom', '下装'),
    L1Category('dress', '连衣裙'),
    L1Category('outer', '外套'),
    L1Category('shoe', '鞋'),
    L1Category('bag', '包'),
    L1Category('acc', '配饰'),
  ];

  static String labelOf(String code) =>
      all.firstWhere((e) => e.code == code, orElse: () => L1Category(code, code))
          .label;
}

const kSeasonAll = 'all';

class Season {
  final String code;
  final String label;
  const Season(this.code, this.label);

  static const all = <Season>[
    Season(kSeasonAll, '四季'),
    Season('spring', '春'),
    Season('summer', '夏'),
    Season('autumn', '秋'),
    Season('winter', '冬'),
  ];

  static String labelOf(String code) => all
      .firstWhere((e) => e.code == code, orElse: () => Season(code, code))
      .label;
}
