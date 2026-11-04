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

# 全部单元测试（底色、排序 SQL、排版输出、分类打分、标签对齐）
flutter test

# 真机上验 ONNX 管线（电脑上跑会是绿的，但模型一次都没跑过）
flutter test integration_test/vision_device_test.dart -d emulator-5554

# 按架构出安装包 → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
flutter build apk --release --split-per-abi
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
- 拍照（App 内连拍）或从相册多选录入，**自动抠图**换纯色底、统一排版（正方形、统一留白）+ 提取主色
- **自动分类**：7 个一级、28 个二级，本地零样本模型，不出网；识别不出就退回一级
- **自动起名**：主色 + 二级类别，如「奶油短袖T恤」，不用打字
- 平铺图底色四档可选（米灰 / 纯白 / 浅灰 / 暖米），只影响以后新加的衣服
- 衣橱排序四种（最近加的 / 最早加的 / 按名称 / 按类别），不影响待确认队列
- 待确认队列：自动分类的结果先进队列，用户翻一遍改错再入库
- 衣服详情：名称、两级类别（一级固定七个、二级可自建）、主色、季节、上身效果图；可删除
- 上身图可写备注（40 字），可重传平铺图（属性与上身图都不动）；只有上身图的衣服有补拍入口
- 身材档案：16 项数据（体重必填、其余选填），按「躯干 / 四肢 / 脚」分组录入，历史记录带与上次的对照
- 身材趋势：体重 / 腰围 / 胸围 / 臀围 / 大腿围 / 臂围 折线图，横轴按真实日期间隔
- 导出为 zip 备份（含头像），支持「合并」与「替换」两种恢复方式
- 十九屏界面由 golden 测试盯着，改动一眼能看出差异；另有 41 个纯函数单元测试

## 模型

`assets/models/` 下三个文件，全部本地推理，不联网、不上传：

| 文件 | 大小 | 用途 |
|---|---|---|
| `seg.onnx` | 4.6 MB | u2netp 抠图，输入 uint8 `[1,320,320,3]` |
| `vision.onnx` | 22.9 MB | MobileCLIP-S0 图像编码器 fp16，输入 uint8 `[1,256,256,3]`，输出 512 维 |
| `labels.json` | 166 KB | 7 个一级 + 28 个二级类别的离线文本向量 |

文本编码器**不在手机上**：标签向量是打包时在电脑上算好的，手机上只跑图像编码器。这是包体能从上百 MB 压到 27 MB 的关键。

两个模型都被改成了「输入 uint8 NHWC」——否则每张图要过 platform channel 序列化 20 万个 float，开销比推理本身还大。

## 还没做

- 上架用的签名（现在是 debug 证书）
- App 图标与启动页（还是 Flutter 默认蓝图标）
- iOS 从没跑过
- 分类只在 16 张干净的网图（Wikimedia 单品照）上验过，家里随手拍的效果未知

## 目录

```
lib/
  models.dart              数据模型
  theme.dart               配色与主题
  data/                    建表 SQL、DAO
  core/
    image_processor.dart   排版、底色、主色提取（纯 Dart）
    vision.dart            ONNX 推理：抠图 + 分类 + 自动起名
    media_store.dart       图片落盘与物理删除
    backup.dart            导出 / 导入
  state/                   ClosetRepository 接口 + SQLite 实现 + Riverpod providers
  ui/                      页面
assets/models/             两个 ONNX 模型 + 离线标签向量
integration_test/
  vision_device_test.dart  真机上验 ONNX 管线
test/
  screens_golden_test.dart 19 个界面的截图测试
  image_processor_test.dart 底色、排序 SQL、排版
  vision_test.dart         归一化、softmax、mask、自动起名
  assets_test.dart         labels.json 与内置类别逐个对齐
  support/                 内存版仓库、字体与假图片生成
```

`ui/` 只依赖 `state/providers.dart` 和 `models.dart`，从不直接碰 DAO。这条线让测试可以整体替换数据源。

**为什么要有 `integration_test/`**：golden 测试跑在电脑的 Flutter 引擎里，`flutter_onnxruntime` 的 platform channel 不存在，`VisionResult` 全是 null——测试是绿的，但模型一次都没跑过。只有在设备上跑才能证明推理真的通。
