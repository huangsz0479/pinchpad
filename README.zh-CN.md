# Pinchpad

**语言 / Language:** [English](README.md) · 简体中文

macOS 菜单栏常驻的**应用启动器与菜单栏应用晾衣绳**。三指捏合展开全屏晾衣绳，快速访问菜单栏应用；点击菜单栏图标直接打开设置；通过四指捏合、快捷键或热角打开完整启动面板，支持文件夹、拖拽排序、搜索和卸载。

- 纯本地应用：不联网、无账号、无遥测。
- 独立实现：不修改、不打包系统自带应用。
- 菜单栏常驻，默认不占程序坞；需要时再呼出面板。

## 功能

**呼出方式**
- 菜单栏图标：左键直接打开设置，右键打开设置与退出菜单
- 三指向内捏合：展开全屏菜单栏应用晾衣绳
- 四指向内捏合：打开完整启动面板
- 已启用的三指或四指展开手势都会关闭当前显示的面板，不受原先打开方式限制
- 四指张开仍交给 macOS 执行「显示桌面」（需在系统设置中开启）；Pinchpad 只拦截向内捏合打开应用面板的动作
- 全局快捷键（默认 `F4`，可在设置里改）和屏幕热角：打开完整启动面板
- 可选的第二个快捷键：打开一个新的终端窗口，工作目录固定为指定目录；目录和终端应用都可配置
- 三指 / 四指手势可在设置里分别开关
- 「设置 → 触控板手势」提供五档捏合灵敏度，平缓调整所需动作幅度；各档均在收拢过程中防抖，正常捏合后可直接抬手，无需额外停住。三指与四指分别调整，立即生效并自动保存；升级时两项均继承原来的共同档位。

**全屏晾衣绳**
- 显示真正拥有菜单栏图标的第三方运行中应用，沿菜单栏实际顺序横向挂开
- 麻绳两端用金属钉固定在菜单栏下边缘约 15 像素处；根据绳长、卡片重力和悬挂位置共同求解绳子形状
- 卡片只比 56 像素图标四周各大 4 像素，左右上角各打一个相同的孔，用两根约 22 像素的细绳连接主绳；两侧拉力、重心和转动惯量共同决定摆动与倾斜，阻尼让它自然停稳
- 整屏背景完全透明，直接透出当前桌面和窗口；仅应用卡片自身使用玻璃材质。停稳及关闭后不持续刷新动画
- 悬挂卡片统一大小。空间不足时分页，使用底部按钮或左右方向键切换
- 每次打开默认不选中应用；默认按 `Tab` 选下一张、按 `~` 所在的键选上一张；两个方向均跨页循环，第一张的上一张是最后一张。设置 → 快捷键与热角可分别录制任意单键（不含 fn、Control、Option、Command、关机），包括 Shift、Caps Lock、方向键、功能键和可接收的媒体键；冲突时交换前后绑定。按空格先立即关闭晾衣绳，再打开选中应用；未选中时空格不执行操作
- 点击卡片打开应用，右键提供打开菜单、前置和退出等操作
- 点击背景、按 `Esc` 或展开手势关闭；跟随现有显示器选择，系统「减弱动态」下直接显示受力平衡后的静态造型

**自由摆放与菜单栏**
- 左键点击 Pinchpad 菜单栏图标直接打开设置；右键仍可打开完整启动面板或退出。旧收纳弹窗已移除。
- 拖动卡片可在屏幕可悬挂区域自由调整横纵坐标，不吸附到固定槽位；位置按应用和屏幕比例保存。
- 起拖时拉力传到整根主绳，超过断开距离后吊绳松脱并回弹；松手后连接点沿主绳移动，绳端穿孔、打结，再由两根吊绳承重。
- 物理以固定 120 Hz 步长求解，显示帧之间插值；原生显示刷新回调随屏幕运行，达到静止阈值或关闭后停止。图标与玻璃内容复用，避免逐帧重建。
- 不移动或隐藏其他应用真正的菜单栏图标。

**浏览与组织**
- 三种浏览方式：分页、纵向滚动、窗口
- 网格密度 7×5 ～ 10×6 可选
- 翻页：`←` `→`、触控板左右滑、底部圆点、两侧箭头
- 拖拽排序（拖到边缘自动翻页）；把一个应用拖到另一个应用上可新建文件夹
- `Cmd` + 点击多选；多选后可新建文件夹或批量隐藏
- 右键菜单：打开、在 Finder 中显示、重命名、隐藏、固定到 Dock、移到废纸篓
- 搜索框实时过滤；按住 `Option` 点击可打开卸载确认框，查看应用及相关支持文件清单
- 「整理应用布局」与「导入系统应用顺序」
- 启用的扫描目录及其子目录会自动同步：新安装的应用追加到现有布局，卸载后自动移除；启动时也会同步关闭期间的变化，保留已有的名称、隐藏状态、文件夹和应用顺序。

**确认弹窗**
- 卸载、重命名和固定到 Dock 的弹窗使用附属于启动面板的原生 sheet，全屏和窗口模式下都显示在面板前方
- 弹窗打开时由它接管键盘焦点，点击背景不会把下面的启动面板关掉
- 取消后不执行对应更改；关闭启动面板时，也会取消尚未处理的确认框

**外观**
- 背景三种样式：墙纸模糊 / 压暗 / 深色
- 打开动画：保留从中心向外的四环图标出场，背景采用原生淡入并按屏幕能力设置刷新率偏好
- 跟随系统「减弱动态」设置

**系统集成**
- 登录时自动启动
- 菜单栏图标、可选程序坞图标
- 打开时临时隐藏程序坞
- 选择面板出现在主屏 / 指针所在屏 / 当前屏
- 多显示器、所有空间、全屏应用之上显示

## 系统要求

- macOS 14（Sonoma）及以上
- Apple Silicon（构建目标为 `arm64-apple-macosx14.0`）
- 构建需使用包含 macOS 26 或更新 SDK 的工具链；部署目标仍为 macOS 14
- 构建需要 Xcode Command Line Tools（`swiftc`、`xcrun`、`codesign`、`security`、`openssl`），不需要 Xcode 工程或 Apple 开发者账号

## 构建

```bash
cd Pinchpad
./build.sh
```

输出：`../Pinchpad.app`（与本项目目录同级）。

说明：

- **构建前先退出正在运行的 Pinchpad**（菜单栏图标右键 → 退出 Pinchpad），否则脚本会拒绝替换正在使用的 app。
- 首次构建会自动生成一套本地自签名身份并保存在 `~/Library/Application Support/Pinchpad/signing/`；之后每次构建沿用同一身份，保证「辅助功能」等系统授权在重新打包后不失效。
- 构建完成后：`open ../Pinchpad.app` 启动，菜单栏出现图标。

重新生成图标（可选）：

```bash
swift generate-icon.swift AppIcon.iconset Resources
```

将 D1 三色折纸图形绘制在扁平米白色 macOS 图标底板上，并以相同折纸轮廓生成单色菜单栏模板。导出全尺寸 `AppIcon.iconset`、`AppIcon.icns`、1024px 的 `Resources/AppIcon-master.png`、可编辑的 `Resources/AppIcon.svg` 和 `Resources/MenuBarIcon.svg`，以及 18pt 的普通及 Retina 菜单栏 PNG。重新构建应用后即可使用更新的图标。

## 使用

| 操作 | 方式 |
|---|---|
| 展开菜单栏应用晾衣绳 | 三指捏合 |
| 打开设置 | 左键点击菜单栏图标 |
| 自由摆放卡片 | 拖动三指捏合面板中的 App 卡片，松手重新系绳 |
| 下一张 / 上一张卡片 | 默认 `Tab` / 波浪号所在键；可在设置里分别更改，循环切换 |
| 打开完整启动面板 | 四指捏合 / 快捷键（默认 `F4`）/ 热角 |
| 关闭完整启动面板 | `Esc`、点击空白处、再次按快捷键，或使用已启用的展开手势 |
| 显示桌面 | 张开拇指和其他三指；需在 macOS 触控板设置中开启「显示桌面」 |
| 翻页 | `←` `→`、触控板左右滑、底部圆点、两侧箭头 |
| 多选 | `Cmd` + 点击 |
| 建文件夹 | 拖一个应用到另一个应用上，或 `Cmd` 多选后点「新建文件夹」 |
| 请求卸载 | `Option` + 点击（可在设置里关闭），或右键 → 移到废纸篓；查看弹窗并确认后才执行 |
| 调整捏合灵敏度 | 设置 → 触控板手势 → 三指 / 四指灵敏度；分别调整 |
| 打开终端 | 设置 → 终端中启用并录制快捷键；每次按下在配置的目录中打开新窗口 |
| 管理应用目录 | 设置 → 应用来源；启用扫描目录或添加自定义文件夹 |
| 设置 | 左键点击菜单栏图标，或右键 → 设置 |

文档提供中英文版本；应用界面目前为简体中文。

设置使用侧栏分为九个页面，无需滚动；应用来源与隐藏应用较多时使用分页。快捷键与热角页面包含三指捏合卡片的前后切换键。菜单栏点击直接打开设置。

### 捏合灵敏度

在 **设置 → 触控板手势** 中分别调整三指和四指灵敏度，共有「很低、低、标准、高、很高」五档，默认使用「标准」。

可以先从「标准」开始：容易误触时调低一档，需要更明确的收拢才触发；正常捏合经常没有反应时调高一档。各档都会过滤短促抖动，捏合后正常抬手即可，无需额外停住。

三指和四指各自有独立滑块，分别启用后即可调整，修改立即生效并在重启后保留。升级时两项均继承旧的共同档位；之后互不影响。

### 应用自动同步

在 **设置 → 应用来源** 中管理扫描目录。默认包括 `/Applications`、`/System/Applications`、`/System/Applications/Utilities` 和 `~/Applications`，也会扫描这些目录的子文件夹。应用放在其他位置时，可通过「添加文件夹…」加入。

- 在已启用的目录中安装应用后，会自动加入现有布局，无需先打开新应用或重新打开面板。请等待文件复制完成、目录变化短暂停稳。
- 卸载应用，或将它移出所有已启用的扫描目录后，会自动移除应用记录、收纳收藏和文件夹中的引用；空文件夹也会一并清理。
- 已有应用的自定义名称、隐藏状态、文件夹和顺序会保留，新发现的应用追加到现有布局中。
- 启用、停用、添加或移除扫描目录后，列表会立即更新；在设置中移除来源不会删除目录中的文件。
- Pinchpad 启动时也会同步关闭期间的安装、卸载变化；需要手动刷新时，仍可点击「重新扫描」。

### 手势与安全卸载

三指向内捏合展开全屏晾衣绳，四指向内捏合打开完整启动面板；展开手势可以关闭当前面板，不要求与打开时的手指数相同。Pinchpad 运行时，系统四指「显示桌面」手势仍然可用，请在 **系统设置 → 触控板 → 更多手势 → 显示桌面** 中开启。

请求卸载不会立即移除任何内容。请先在确认弹窗中查看应用及列出的支持文件，明确确认后才会将它们移到废纸篓；点击「取消」则保持原样。Pinchpad 不会移除自身或 `/System` 下的应用。

### 终端快捷键

在 **设置 → 终端** 中配置打开终端窗口的独立快捷键。

- 打开开关后点「录制更改」，和面板快捷键一样录制任意组合键。
- 「启动目录」：每次打开的新终端窗口都从这个目录开始；留空表示用户主目录，也可点「选择…」挑选文件夹。
- 「终端应用」：默认使用系统自带 Terminal.app；也可以换成 iTerm 等能把文件夹作为新会话打开的终端。

启动面板或晾衣绳打开时按下该快捷键，会先收起当前面板再激活终端。配置的目录不存在时，Pinchpad 会提示而不是落到别的目录。

## 本地数据

| 路径 | 内容 |
|---|---|
| `~/Library/Application Support/Pinchpad/library.json` | 设置、应用列表、已收纳应用、文件夹、分页、当前页。删除后重开会重新扫描并生成默认布局 |
| `~/Library/Preferences/app.local.pinchpad.plist` | 系统偏好占位文件（基本为空） |
| `~/Library/Application Support/Pinchpad/signing/` | 本地签名钥匙串与 p12（构建用；**勿删**，否则无法替换现有 app） |

图标位图、背景光晕渐变、面板预热纹理等缓存**只在内存中**，退出即释放，不写磁盘缓存目录。

## 签名与权限

- 使用构建脚本在本机生成的**自签名证书** `Pinchpad Local`（RSA 2048，有效期 10 年），不访问网络、不使用 Apple ID 或开发者证书。
- 签名身份保存在 `~/Library/Application Support/Pinchpad/signing/`（`pinchpad.keychain-db` 与 `pinchpad.p12`），密码为 `pinchpad-local`，仅用于这个独立钥匙串，与登录钥匙串无关。
- 触控板捏合、菜单栏应用识别及「打开菜单」需要「系统设置 → 隐私与安全性 → 辅助功能」授权；保持签名身份不变，重新打包后无需重新授权。
- 未做公证（notarization），仅适合本机使用。

## 项目结构

```
Pinchpad/
├── Sources/
│   ├── AppMain.swift          # 入口、面板窗口、菜单栏、热角/捏合接线、淡入淡出、背景光晕
│   ├── AppModel.swift         # 全局状态、数据持久化、图标缓存、拖拽、分页、卸载、导入
│   ├── AppLibraryMonitor.swift # 应用目录变动监听与安装事件防抖
│   ├── PanelAlertPresenter.swift # 附属于启动面板的原生确认弹窗
│   ├── IconEntrance.swift      # 原有图标波纹时序与可见性规则
│   ├── EntranceMotion.swift    # 独立入场信号，复用已挂载的图标网格
│   ├── PanelAnimation.swift     # 合成器过渡与屏幕刷新率适配
│   ├── LauncherPanelVisibility.swift # 隐藏面板与特效的停用
│   ├── Model.swift            # 数据模型与偏好设置
│   ├── PinchpadView.swift     # 主界面：搜索、网格、分页、文件夹、入场动画
│   ├── PagingMotion.swift     # 仅由翻页区域观察的连续滑动状态
│   ├── TrayView.swift         # 液态玻璃收纳面板、菜单栏应用、钉选与添加
│   ├── SettingsView.swift     # 设置侧栏、分区与通用卡片
│   ├── GestureSettingsView.swift # 手势、快捷键、终端设置
│   ├── PanelSettingsView.swift # 通用、外观、布局与关于
│   ├── ApplicationSettingsView.swift # 分页的来源与隐藏应用
│   ├── SettingsControls.swift # 快捷键录制与整理弹窗
│   ├── SettingsPagination.swift # 设置列表分页边界
│   ├── Services.swift         # 应用扫描、卸载相关文件、Dock 固定、全局热键、热角、捏合监听
│   └── PinchClassifier.swift  # 触控板多指手势判定
├── Tests/
│   ├── PanelTransitionProbe.swift # 完整面板开关、动画与构建一致性检查
│   ├── PanelAnimationProbe.swift # 内存中的动画与刷新率约定检查
│   ├── IdleResponsivenessProbe.swift # 隐藏窗口与输入线程隔离检查
│   ├── AlertPresentationProbe.swift # 全屏/窗口模式的弹窗层级与取消检查
│   ├── PinchGestureProbe.swift    # 手势识别与三指/四指面板路由检查
│   ├── PageNavigationProbe.py     # 方向键单次翻页与事件传递检查
│   ├── PagingPerformanceProbe.py # 隔离的 SwiftUI 翻页开销与命中区域检查
│   ├── OpeningPerformanceProbe.py # 隐藏容器中的打开开销与图标波纹生命周期检查
│   ├── TrayOpeningProbe.py      # 使用模拟应用检查收纳面板打开与异步刷新
│   ├── AppLibrarySyncProbe.py     # 安装/卸载自动同步、启动校准与扫描目录变化检查
│   ├── TrayActivationProbe.swift  # 图标点击、轻微拖动与辅助功能按压
│   ├── TrayCornerProbe.swift      # 圆角外侧像素透明度检查
│   ├── TrayPlacementProbe.swift   # 菜单栏下方 8 点间距与窗口层级检查
│   └── TerminalDirectoryProbe.swift # 终端启动后新 shell 落在配置目录的检查
├── Resources/                 # 应用图标原稿与菜单栏图标
├── AppIcon.iconset/           # 各尺寸应用图标
├── AppIcon.icns
├── Info.plist
├── generate-icon.swift        # 生成应用图标与菜单栏图标
└── build.sh                   # 编译、组装、签名、校验
```

## 性能说明

- 隐藏面板移出显示列表并停用毛玻璃，保留视图和图标缓存。
- 完整启动面板保留从中心向外的四环图标出场，背景使用原生淡入淡出；仅当前页播放入场，同一环的图标一起合成。晾衣绳使用实时耦合物理模拟和屏幕同步刷新。
- 入场信号直接更新波纹动画层，重新打开时复用已经挂载的图标网格。
- 面板淡入淡出会在支持的屏幕上请求优先 120 帧，刷新率偏好不会超过屏幕能力；该偏好不代表已经测得或保证翻页动画达到相同帧率。
- 触控板连续滑动只更新翻页区域；滑动期间暂停图标命中区域计算，静止时只收集当前页，拖拽时恢复相邻页坐标以支持边缘翻页。
- 翻页所需的水平距离限制在 36–60 点，大屏幕不再要求更远的拖动；短促滑动保留最小位移要求以过滤抖动。
- 拖拽重排时图标保留原有视图身份，避免跨入场分组时销毁重建；经过其他图标不会撤销排列预览，停留后才进入文件夹合并状态。跨页排列合并为一次状态更新。
- 最多缓存连续三页，首尾位置也保持这个缓存窗口，避免三页应用库来回翻页时反复创建暂时不可见的整页图标。
- 全局手势拦截使用独立运行循环，界面工作不会阻塞全局手势处理。
- 菜单栏应用在打开晾衣绳及应用启动/退出时后台刷新；面板先显示缓存，重叠请求会合并，过期结果不会覆盖新状态。
- 应用库通过 macOS 文件事件监听启用的目录，合并安装过程中的连续变化后在后台扫描；空闲时不轮询，扫描目录的启用、停用和增删会立即生效。
- 实际耗时与资源占用取决于系统、设备和应用数量，可使用以下探针检查当前构建。

## 测试

全屏晾衣绳使用离线几何、生命周期模拟和离屏渲染检查，不打开测试窗口或读取桌面：

```bash
swiftc -O -swift-version 5 -parse-as-library Sources/Model.swift Sources/ClotheslinePreferences.swift Sources/PinchClassifier.swift Sources/ClotheslineLayout.swift Tests/ClotheslineLayoutProbe.swift -o /tmp/ClotheslineLayoutProbe && /tmp/ClotheslineLayoutProbe
swiftc -O -parse-as-library Sources/Model.swift Sources/PinchClassifier.swift Sources/ClotheslinePreferences.swift Sources/ClotheslineLayout.swift Sources/ClotheslineDynamics.swift Tests/ClotheslineDynamicsProbe.swift -o /tmp/ClotheslineDynamicsProbe && /tmp/ClotheslineDynamicsProbe
swiftc -O -parse-as-library Sources/Model.swift Sources/PinchClassifier.swift Sources/ClotheslinePreferences.swift Sources/CardKeyEditor.swift Tests/CardNavigationProbe.swift -o /tmp/CardNavigationProbe && /tmp/CardNavigationProbe
python3 Tests/ClotheslineLifecycleProbe.py
python3 Tests/ClotheslineRoutingProbe.py
python3 Tests/ClotheslineRenderProbe.py
python3 Tests/ClotheslineIconAlignmentProbe.py
python3 Tests/ClotheslineTransparencyProbe.py
```

离屏图片保存在 `.build/clothesline/review/`，覆盖明暗外观、窄屏、超宽屏、空列表和动画关键帧。图片用于检查布局；实际桌面玻璃合成与触控板手感需手动验收。

```bash
swift Tests/PanelTransitionProbe.swift <运行中的 Pinchpad PID> <源码根目录>

# 不需要触控板或运行中的应用，检查手势识别与面板路由：
swiftc -swift-version 5 Sources/Model.swift Sources/ClotheslinePreferences.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Tests/PinchGestureProbe.swift -lsqlite3 \
  -o /tmp/PinchGestureProbe && /tmp/PinchGestureProbe

# 不发送系统输入、不读取个人应用库，检查方向键单次翻页与事件传递：
python3 Tests/PageNavigationProbe.py

# 回放短距离翻页、快速轻扫、防误触、取消和边界；不显示窗口：
python3 Tests/PagingThresholdProbe.py

# 离屏检查拖动视图身份、预览稳定、文件夹合并、跨页顺序与入场分组：
python3 Tests/DragPerformanceProbe.py

# 离屏检查设置页及下拉控件：
python3 Tests/SettingsLayoutProbe.py
python3 Tests/SettingsPickerAlignmentProbe.py

# 在独立且不显示的 SwiftUI 容器中回放滑动，检查更新量，不测屏幕实际帧率：
python3 Tests/PagingPerformanceProbe.py --check

# 隐藏容器中的打开/布局与原有波纹检查，不测窗口服务器或 GPU 的实际帧率：
python3 Tests/OpeningPerformanceProbe.py --check

# 模拟菜单栏查询，不读取或操作其他应用界面：
python3 Tests/TrayOpeningProbe.py

# 只创建临时应用包，不操作界面或个人应用库，检查安装/卸载与扫描目录同步：
python3 Tests/AppLibrarySyncProbe.py

# 不创建窗口、不依赖运行中的应用，检查动画与刷新率偏好：
swiftc Sources/IconEntrance.swift Sources/PanelAnimation.swift Tests/PanelAnimationProbe.swift \
  -o /tmp/PanelAnimationProbe && /tmp/PanelAnimationProbe

# 不发送系统输入、不显示窗口，检查输入线程与面板停用：
swiftc -swift-version 5 Sources/Model.swift Sources/ClotheslinePreferences.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Sources/LauncherPanelVisibility.swift \
  Tests/IdleResponsivenessProbe.swift -lsqlite3 \
  -o /tmp/IdleResponsivenessProbe && /tmp/IdleResponsivenessProbe

# 原生确认框层级检查；测试只取消，不会删除任何内容：
swiftc -swift-version 5 Sources/PanelAlertPresenter.swift \
  Tests/AlertPresentationProbe.swift -o /tmp/AlertPresentationProbe \
  && /tmp/AlertPresentationProbe

# 终端启动链路：在临时目录里真实打开一个终端窗口，
# 检查新出现的 shell 工作目录是否为该目录：
swift Tests/TerminalDirectoryProbe.swift "$(mktemp -d)"
```

探针覆盖：

- 原有波纹动画的时序与可见性、背景淡入端点、快速开关，以及 60/120/144/240 Hz 的刷新率偏好。内存检查不等同于实际显示帧率，后者需要在目标屏幕上实测。
- 构建一致性与完整启动面板的打开/关闭过渡。
- 隔离 SwiftUI 容器中的连续滑动更新范围、实际页面位移、命中区域恢复和翻页行为；耗时仅涵盖输入处理及强制布局，不包含可见窗口合成和 GPU 开销。
- 菜单栏直达设置；晾衣绳的自由放置、拖拽断开与重新系绳、循环选卡，以及点击打开应用。
- 五档灵敏度、即时调整和旧设置迁移；三指/四指面板路由、系统「显示桌面」事件放行，以及系统左右/上下滑动的保留。
- 安装/卸载自动同步、关闭期间的变化、嵌套与重建的目录、路径别名、应用移动、元数据与布局保留、过期扫描结果丢弃及空闲行为；应用库探针只增删临时测试文件。
- 全屏/窗口模式下确认弹窗位于启动面板前方，且取消后面板仍然可见。
- 终端启动：经 Launch Services 交给终端应用的文件夹会成为新 shell 的工作目录；探针会在临时目录里真实打开一个终端窗口。

启动探针还支持 `drift`（轻微拖动）和 `ax`（辅助功能按压）模式。手势探针不安装设备监听，也不需要运行中的应用。弹窗探针只打开测试对话框并取消，不会删除任何内容。与实际应用交互的测试需要为终端或宿主程序授予相应的辅助功能、截屏及自动化权限。

## 常见问题

| 现象 | 处理 |
|---|---|
| 构建提示 `Quit the running Pinchpad before rebuilding...` | 先从菜单栏退出正在运行的 Pinchpad |
| 构建提示 `requires its original signing identity` / `Signing certificate does not match` | 签名目录丢失或被替换：恢复 `signing/` 目录，或同时删除 `Pinchpad.app` 和 `signing/` 后重新构建（会生成新身份，需要重新授予辅助功能） |
| 捏合手势不生效 | 在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Pinchpad；确认设置里对应的三/四指捏合已开启 |
| 捏合容易误触，或正常捏合经常没反应 | 在「设置 → 触控板手势 → 捏合灵敏度」中调整：误触时调低，漏触发时调高；三指和四指分别调整 |
| 四指张开不能显示桌面 | 在「系统设置 → 触控板 → 更多手势」中开启「显示桌面」，并使用已修复该手势拦截问题的新版 Pinchpad |
| 确认弹窗被启动面板遮挡 | 更新代码并重新构建；新版使用附属于面板的原生 sheet，不再依赖手动提高窗口层级 |
| 菜单栏区没有应用 | 授予 Pinchpad 辅助功能权限后重新打开面板；该区域只显示拥有菜单栏图标的第三方应用，不是所有运行中的应用 |
| 快捷键无反应 | 快捷键可能被系统或其他应用占用，设置里会给出提示，可更换组合键 |
| 首次打开稍慢 | 与登录后首次激活 app、初始化键盘焦点有关，是一次性开销 |
| 新装应用没出现，或已卸载应用仍然保留 | 等待安装完成，在「设置 → 应用来源」中确认所在目录已启用，必要时点击「重新扫描」；应用放在其他位置时先添加自定义目录 |
| 想调整应用顺序 | 拖拽图标，在「设置 → 布局与整理」中使用「整理应用布局」，或在「设置 → 应用来源」中选择「导入系统应用顺序」 |

## 卸载

1. 从菜单栏退出 Pinchpad。
2. 删除 `Pinchpad.app`。
3. 删除 `~/Library/Application Support/Pinchpad/`（设置、布局与签名身份都在这里）。
4. 在「系统设置 → 通用 → 登录项」与「隐私与安全性 → 辅助功能」中移除 Pinchpad。

## 许可证

本项目基于 **MIT License** 开源，详见 [LICENSE](LICENSE)。

Copyright (c) 2026 huangsz
