# 明天穿什么

私人的、多角色的服装相册。把衣服拍进来、自动整理成统一的样子、随时翻。

**不做**推荐、不做虚拟试衣、不做社交、不接天气。第一版只解决两件事：**录入够不够快**、**相册看起来够不够整齐**。

## 跑起来

需要 Flutter 3.47+。本机已装好 Android SDK 36 与 JDK 17，可以直接打 APK。

```powershell
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$env:JAVA_HOME = "D:\android_dev\jdk\jdk-17.0.2"
$env:ANDROID_HOME = "D:\android_dev\sdk"

flutter pub get

# 静态检查
dart analyze lib test

# 渲染 19 张界面截图到 test/goldens/，然后人眼核对
flutter test --update-goldens test/screens_golden_test.dart

# 纯函数单元测试（底色、排序 SQL、排版输出）
flutter test test/image_processor_test.dart

# 打安装包 → build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release
```

`flutter analyze` 在某些中文路径下会崩在 analysis server 的 LSP 初始化上，用 `dart analyze` 代替即可。

## 两台机器上踩过的坑（改构建配置前先读）

工程原本放在 `D:\明天穿什么`，Android 构建在三个地方栽过跟头，现在都写进了 `android/` 里：

| 现象 | 原因 | 处理 |
|---|---|---|
| `Your project path contains non-ASCII characters` | AGP 默认拒绝含中文的路径 | 工程已改名为 `D:\mingtian-chuanshenme`；`android.overridePathCheck=true` 留着兜底 |
| `AOT snapshotter exited with code 255` / `Unable to read file: D:\���촩ʲô\...app.dill` | Dart AOT 快照器读不了中文路径 | 同上，改路径才是根治 |
| `this and base files have different roots` | pub 缓存在 C 盘、工程在 D 盘，Kotlin 增量编译无法跨盘相对化 | `kotlin.incremental=false` + `org.gradle.daemon=false` |
| `:file_picker is currently compiled against android-34` | 插件自己钉死 compileSdk 34，而上层要求 36 | `android/build.gradle.kts` 里给所有 subproject 抬到 36 |
| `Failed to apply plugin: cmake;3.22.1` | NDK/CMake 首次构建要下载 | 已装好，留在 `D:\android_dev\sdk` |

另外 `sqflite_common_ffi` 已从依赖里去掉：它只在桌面端测试用，但会触发 dart hook 去 GitHub 下载预编译的 `libsqlite3.so`，在打 Android 包时直接失败。测试用的是内存版 `FakeRepository`，不需要它。

## 现在能做什么

- 多角色，各自独立的衣橱，互不可见；角色可拖动排序、可改名换头像、可删除（名下衣服与图片一并清掉）
- 拍照（App 内连拍）或从相册多选录入，自动统一排版（正方形、统一底色、统一留白）+ 提取主色
- 平铺图底色四档可选（米灰 / 纯白 / 浅灰 / 暖米），只影响以后新加的衣服
- 衣橱排序四种（最近加的 / 最早加的 / 按名称 / 按类别），不影响待确认队列
- 待确认队列：自动分类的结果先进队列，用户翻一遍改错再入库
- 衣服详情：名称、两级类别（一级固定七个、二级可自建）、主色、季节、上身效果图；可删除
- 上身图可写备注（40 字），可重传平铺图（属性与上身图都不动）；只有上身图的衣服有补拍入口
- 身材档案：16 项数据（体重必填、其余选填），按「躯干 / 四肢 / 脚」分组录入，历史记录带与上次的对照
- 身材趋势：体重 / 腰围 / 胸围 / 臀围 / 大腿围 / 臂围 折线图，横轴按真实日期间隔
- 导出为 zip 备份（含头像），支持「合并」与「替换」两种恢复方式
- 十九屏界面由 golden 测试盯着，改动一眼能看出差异；另有一组纯函数单元测试

## 还没做

- 抠图（分割模型未接入，现在只排版不抠图）
- 自动分类（零样本 CLIP 未接入）

## 目录

```
lib/
  models.dart              数据模型
  theme.dart               配色与主题
  data/                    建表 SQL、DAO
  core/                    图像处理、媒体文件、备份
  state/                   ClosetRepository 接口 + SQLite 实现 + Riverpod providers
  ui/                      页面
test/
  screens_golden_test.dart 19 个界面的截图测试
  image_processor_test.dart 纯函数单元测试（底色、排序 SQL、排版）
  support/                 内存版仓库、字体与假图片生成
```

`ui/` 只依赖 `state/providers.dart` 和 `models.dart`，从不直接碰 DAO。这条线让测试可以整体替换数据源。
