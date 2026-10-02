# 交接文档：scheduled-tapper 定制版（UI 精简 + 多点取点）

> 用途：本文件用于把当前工作交接给新的对话/会话继续完成。读完本文件即可无缝接手。

---

## 1. 项目基本信息

- **项目路径**：`C:\sdt\scheduled-tapper`（英文路径，重要！原中文路径会导致 `includeBuild` 失败）
- **来源**：`Seaky0201/scheduled-tapper`（定时连点器，Flutter + Kotlin 原生悬浮窗/无障碍）
- **包名**：`com.dsh.tapper`，版本 1.7.1
- **目标手机**：Redmi K20 Pro，adb 序列号 `c940a96d`，有 user 0（owner）+ user 10（安全空间），安装用 `adb install --user 0 -r <apk>`
- **当前 APK 大小**：17.09 MB（release，仅 arm64）

## 2. 构建与部署（每次都要用的环境变量与命令）

工具链都在项目内 `.toolchain\`（flutter 3.47.6 + Dart 3.13.5、gradle-9.3.1、jdk17、android-sdk），**不依赖系统安装**。

PowerShell 中每次构建前设置：

```powershell
$tc = "C:\sdt\scheduled-tapper\.toolchain"
$root = "C:\sdt\scheduled-tapper"
$env:JAVA_HOME = "$tc\jdk17"
$env:ANDROID_HOME = "$tc\android-sdk"
$env:ANDROID_SDK_ROOT = "$tc\android-sdk"
$env:FLUTTER_STORAGE_BASE_URL = "https://mirrors.tuna.tsinghua.edu.cn/flutter"
$env:PUB_HOSTED_URL = "https://mirrors.tuna.tsinghua.edu.cn/dart-pub"
$flutter = "$tc\flutter\bin\flutter.bat"
Set-Location $root
```

构建（约 1-2 分钟）：

```powershell
& $flutter build apk --release --target-platform android-arm64
```

安装并重启：

```powershell
$adb = "$root\.toolchain\android-sdk\platform-tools\adb.exe"
$apk = "$root\build\app\outputs\flutter-apk\app-release.apk"
& $adb install --user 0 -r "$apk"
& $adb shell am force-stop com.dsh.tapper
& $adb shell am start -n com.dsh.tapper/.MainActivity
```

**已知坑**：
- `flutter analyze` / `flutter build` 会把 banner 写到 stderr，PowerShell 会误报 exit code 1。**看日志内容（"No issues found" / "✓ Built ..."）判断，不要看 exit code**。
- 网络：dl.google.com、plugins.gradle.org、services.gradle.org 不可达；已配置腾讯/清华/阿里云镜像（见 `android/build.gradle.kts`、`android/settings.gradle.kts`、`android/gradle/wrapper/gradle-wrapper.properties`）。Flutter engine 产物只有 `https://mirrors.cloud.tencent.com/flutter/download.flutter.io` 可用。
- 移动项目目录后如报大量"undefined"编译错误：删 `.dart_tool` 再 `flutter pub get`。

## 3. 用户偏好（重要）

- **用户明确要求：不要调用任何视觉功能**（不要看图、截图、browser.preview 等）。一切靠代码与几何推理确认。
- 用户偏好极简 UI：能删的入口都删，不接受多余按钮/折叠/菜单。

## 4. 已完成的全部改动（按时间顺序，已全部构建安装到手机）

最近一次成功构建安装 = **build15**（17.92MB，待办 A 固定悬浮球宽度）。build14（17.09MB）为此前版本。

1. **权限 chip 可点击**：状态卡片上的「无障碍」「悬浮窗」chip 直接点击跳系统设置（`main.dart` `_chip`，ActionChip）。
2. **日志美化**：深色渐变背景、按级别着色（ERROR/WARN/OK/TEST/WAIT）、每行 时间+级别徽章+消息，行内可选中复制（`_logCard`/`_logLineWidget`）。
3. **添加时间点简化**：改为 3 个 CupertinoPicker 滚轮（时/分/秒）单选一个时间点（`dialogs.dart` `showTimeDialog`/`_timeWheel`），**默认当前时间**，编辑时从现有点初始化。`TimeEditResult` 返回单元素列表。
4. **分组 UI 全部移除**：分组 FAB、分组区块渲染、「分组」菜单、分组对话框全删；`models.dart` 里 `groups`/`groupId` **保留在数据模型**（数据兼容 + 不动原生）。
5. **状态卡片「设置」菜单按钮移除**；删了不再用的 `_panelOpen`。
6. **日志默认展开**：`_logOpen` 默认 true（后续第 9 步又进一步固定展开并删了该字段）。
7. **状态卡片「选点导入」按钮移除**（取点只在时间点卡片内做）。
8. **状态卡片收缩/展开按钮移除**：状态详情（下次触发/系统时区）固定直接显示；删 `_statusDetailOpen`。
9. **日志收缩/展开按钮移除**：日志固定常驻展开；删 `_logOpen`。
10. **悬浮窗面板只留取点**：点悬浮球展开的面板（`OverlayService.kt openPanel()`）现在只有：标题+下次触发、**「选取位置（取点）」按钮**、「收起面板」。删掉了时间源切换、北京对时、±100ms/归零、选点导入、测试时间点、显示/隐藏、刷新配置、中止、打开主界面等按钮。**注意**：`openPicker()`/`openTestPicker()` 等函数本体仍保留（未被面板调用，降低风险未删）。
11. **AppBar 右上角「清空日志」删除按钮移除**。
12. **多点连击取点**（本次重点，build13/14）：
    - 原生 `CatcherView.onTouchEvent`：去掉 450ms 自动退出（`handler.postDelayed({ exitPickMode() }, 450L)` 已删），改为持续记录；`pendingSteps = pendingSteps + Step(...)` 累积。
    - 新增「完成取点」悬浮按钮：`OverlayService` 加了 `doneBtn`/`doneBtnLp` 字段和 `addDoneButton()`（红色圆角 TextView，位置 TOP|END，点击调 `exitPickMode()`）；`enterPickMode()` 在添加 catcher 后调用 `addDoneButton()`，`exitPickMode()` 里移除 doneBtn。
    - Flutter `_onPicked`：不再每次 pick 后清空 `_pickTarget`（改在收到 `active=false` 时统一清空，该逻辑原本就在 `_pickSub` 里）。`new|id` tag 下每次 pick 追加一步。
    - 交互：时间点卡片 →「悬浮窗取点添加步骤」→ 连续点多个位置 → 点「完成取点」结束。
13. **新应用图标**：`android/app/src/main/res/drawable/ic_tapper.xml` 重画为 108dp 矢量图：圆角蓝底(#1565C0) + 白色目标环 + 红色目标环(#FF1744) + 浅粉外环(#FFCDD2) + 白色时/分针（指向3点）+ 黄色中心点(#FFC107)。主题=时钟(定时)+靶心(连击)。AndroidManifest 用 `android:icon="@drawable/ic_tapper"`（无 adaptive icon/mipmap）。
14. **悬浮球固定宽度**（待办 A，build15）：`ensureOverlay()` 里悬浮球窗口宽度由 `WRAP_CONTENT` 改为固定 `dp(140)`，`box` 改为 `MATCH_PARENT` 铺满；时钟行与状态行分别 `maxLines`/`ellipsize=END` 限制，宽度不再随内容文字变化，实现「一直保持紧凑」。**待办 B（单击保持面板）经用户确认无需改动**。

## 5. 待办事项（两项目前均已处理完，仅供参考）

用户原话（可能有个别错别字）：

> 「为什么移动那个悬浮窗的时候会缩短，改成一直缩短，还有就是要提斯点击这个悬浮窗可以展开取点操作」

拆解为两个任务：

### 待办 A：悬浮球"移动时会缩短"→"改成一直缩短"（**已完成 build15**）
- **现象**：用户拖动悬浮球时它会缩短（变小/变窄）。用户希望它**一直保持缩短（紧凑）状态**。
- **已确认方案**：用户选「保留时钟但固定宽度」——保留时钟行与状态行，把整个悬浮球宽度固定，不再随内容文字长短变化。
- **已实现改动**（`OverlayService.kt` `ensureOverlay()`）：
  - 悬浮球窗口 `lp.width` 由 `WRAP_CONTENT` 改为固定 `dp(140)`（`val fixedBubbleW = dp(140)`）。
  - `box` 以 `MATCH_PARENT` 横向铺满 root 固定宽度（原 `WRAP_CONTENT`）。
  - `clock` 增加 `setMaxLines(1)` + `ellipsize = END`（时间源不可用时的长文案不再撑大变高）。
  - `label`（状态行）增加 `maxLines = 2` + `ellipsize = END`（「下次 无（没有启用的时间点）」等长文案省略号截断、不再撑宽/撑高）。
  - 新增 import `android.text.TextUtils`。
- **注意**：时钟行宽约 96dp、box 内容宽 116dp，dp(140) 足够容纳；宽度不再跟随状态文字/时钟长度变化。悬浮球高度仍可因状态 1~2 行而略有变化（用户只要求固定宽度）。

### 待办 B：点击悬浮窗展开取点操作（**已确认：保持面板，无需改动**）
- **用户已确认**：单击悬浮球保持现在「展开面板」的行为（面板里只剩「选取位置（取点）」「收起面板」两个按钮），**不**改为单击直接进取点。因此**本轮未做任何变更**。
- 若有改主意：把 `root.setOnTouchListener` 的 `ACTION_UP` 分支里 `ACTION_OPEN_PANEL -> openPanel()` 改为 `enterPickMode()`（长按仍隐藏）。改后面板即成死代码可一并清理。

## 6. 关键文件清单

| 文件 | 作用 |
|---|---|
| `lib/main.dart` | 主 UI：状态卡片/chip、平铺时间点列表、`_logCard`/`_logLineWidget`、取点状态机（`_pickTarget`/`_onPicked`/`_pickFor`）、AppBar |
| `lib/dialogs.dart` | `showTimeDialog`（3 滚轮）、`showDelayDialog`、`showCoordDialog`、`TimeEditResult` |
| `lib/models.dart` | `TapperConfig`/`TimePoint`/`TapStep`/`PointGroup`（分组字段仅为兼容保留） |
| `lib/native.dart` | MethodChannel/EventChannel 桥（`openAccessibilitySettings`/`openOverlaySettings`/`enterPickMode` 等） |
| `android/app/src/main/kotlin/com/dsh/tapper/OverlayService.kt` | 悬浮球、面板、取点模式（`ensureOverlay`/`openPanel`/`enterPickMode`/`exitPickMode`/`CatcherView`/`addDoneButton`） |
| `android/app/src/main/kotlin/com/dsh/tapper/TapMath.kt` | `BubbleGesture.decide` 手势判定、`BubbleStatus.text`、坐标换算等纯逻辑 |
| `android/app/src/main/res/drawable/ic_tapper.xml` | 应用图标（108dp 矢量） |
| `android/app/build.gradle.kts` | app 构建（arm64 abiFilters） |
| `android/build.gradle.kts` | allprojects 仓库（含腾讯 engine 镜像） |
| `android/settings.gradle.kts` | 插件仓库（阿里云）、`includeBuild` flutter gradle |
| `android/gradle/wrapper/gradle-wrapper.properties` | distributionUrl 指向腾讯 bin.zip 镜像 |

## 7. 验证过的命令

- `flutter analyze` → "No issues found"
- `flutter build apk --release --target-platform android-arm64` → 产物 `build\app\outputs\flutter-apk\app-release.apk`（本会话 build15 = 17.92MB；PowerShell 可能误报 exit code 1，以「✓ Built ...」判断）
- 安装成功：`Success`；重启：`am start -n com.dsh.tapper/.MainActivity`
