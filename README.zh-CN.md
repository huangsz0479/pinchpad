# Pinchpad

**语言 / Language:** [English](README.md) · 简体中文

macOS 菜单栏常驻的**应用启动器与收纳面板**。从菜单栏或三指捏合打开轻量收纳面板，快速访问菜单栏应用和手动收纳的常用应用；通过四指捏合、快捷键或热角打开完整启动面板，支持文件夹、拖拽排序、搜索和卸载。

- 纯本地应用：不联网、无账号、无遥测。
- 独立实现：不修改、不打包系统自带应用。
- 菜单栏常驻，默认不占程序坞；需要时再呼出面板。

## 功能

**呼出方式**
- 菜单栏图标：左键打开/关闭收纳面板，右键打开设置与退出菜单
- 三指向内捏合：打开收纳面板
- 四指向内捏合：打开完整启动面板
- 已启用的三指或四指展开手势都会关闭当前显示的面板，不受原先打开方式限制
- 四指张开仍交给 macOS 执行「显示桌面」（需在系统设置中开启）；Pinchpad 只拦截向内捏合打开应用面板的动作
- 全局快捷键（默认 `F4`，可在设置里改）和屏幕热角：打开完整启动面板
- 三指 / 四指手势可在设置里分别开关
- 「设置 → 手势与按键」提供五档捏合灵敏度，平缓调整所需动作幅度；各档均在收拢过程中防抖，正常捏合后可直接抬手，无需额外停住。三指和四指共用，调整立即生效并自动保存。

**菜单栏收纳**
- 「菜单栏」区只显示真正拥有菜单栏图标的第三方应用，按图标的实际左右顺序排列
- 「已收纳」区保存手动钉选的常用应用，重启后仍保留
- 点击「添加」直接搜索并收纳应用，也可在完整启动面板中右键选择「收进菜单栏」
- 点击图标打开或前置应用；右键可取消收纳，菜单栏应用还支持「打开菜单」
- macOS 26 及以上使用原生液态玻璃，旧系统回退到系统材质
- 面板宽 460 点，每行 5 个应用，菜单栏下方留 2px；底部避开 Dock、保留 6 点间距后再上收 200px，支持点击外部或按 `Esc` 关闭
- 不移动或隐藏其他应用真正的菜单栏图标

**浏览与组织**
- 三种浏览方式：分页、纵向滚动、窗口
- 网格密度 7×5 ～ 10×6 可选
- 翻页：`←` `→`、触控板左右滑、底部圆点、两侧箭头
- 拖拽排序（拖到边缘自动翻页）；把一个应用拖到另一个应用上可新建文件夹
- `Cmd` + 点击多选；多选后可新建文件夹或批量隐藏
- 右键菜单：打开、在 Finder 中显示、收进菜单栏、重命名、隐藏、固定到 Dock、移到废纸篓
- 搜索框实时过滤；按住 `Option` 点击可打开卸载确认框，查看应用及相关支持文件清单
- 「整理应用布局」与「导入系统应用顺序」

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
swift generate-icon.swift <输出.iconset 目录> <菜单栏图标输出目录>
```

## 使用

| 操作 | 方式 |
|---|---|
| 打开收纳面板 | 左键点击菜单栏图标，或三指捏合 |
| 打开完整启动面板 | 四指捏合 / 快捷键（默认 `F4`）/ 热角 / 收纳面板底部「全部应用」 |
| 关闭收纳面板 | `Esc`、点击外部、再次点击菜单栏图标，或使用已启用的展开手势 |
| 关闭完整启动面板 | `Esc`、点击空白处、再次按快捷键，或使用已启用的展开手势 |
| 显示桌面 | 张开拇指和其他三指；需在 macOS 触控板设置中开启「显示桌面」 |
| 收纳应用 | 收纳面板中点击「添加」，或在完整启动面板里右键 → 收进菜单栏 |
| 取消收纳 | 右键点击已收纳的应用 → 取消收纳 |
| 翻页 | `←` `→`、触控板左右滑、底部圆点、两侧箭头 |
| 多选 | `Cmd` + 点击 |
| 建文件夹 | 拖一个应用到另一个应用上，或 `Cmd` 多选后点「新建文件夹」 |
| 请求卸载 | `Option` + 点击（可在设置里关闭），或右键 → 移到废纸篓；查看弹窗并确认后才执行 |
| 设置 | 菜单栏图标右键 → 设置 |

文档提供中英文版本；应用界面目前为简体中文。

### 手势与安全卸载

三指和四指向内捏合分别打开不同的 Pinchpad 面板；展开手势可以关闭当前面板，不要求与打开时的手指数相同。Pinchpad 运行时，系统四指「显示桌面」手势仍然可用，请在 **系统设置 → 触控板 → 更多手势 → 显示桌面** 中开启。

请求卸载不会立即移除任何内容。请先在确认弹窗中查看应用及列出的支持文件，明确确认后才会将它们移到废纸篓；点击「取消」则保持原样。Pinchpad 不会移除自身或 `/System` 下的应用。

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
│   ├── PanelAlertPresenter.swift # 附属于启动面板的原生确认弹窗
│   ├── IconEntrance.swift      # 原有图标波纹时序与可见性规则
│   ├── PanelAnimation.swift     # 合成器过渡与屏幕刷新率适配
│   ├── LauncherPanelVisibility.swift # 隐藏面板与特效的停用
│   ├── Model.swift            # 数据模型与偏好设置
│   ├── PinchpadView.swift     # 主界面：搜索、网格、分页、文件夹、入场动画
│   ├── TrayView.swift         # 液态玻璃收纳面板、菜单栏应用、钉选与添加
│   ├── SettingsView.swift     # 设置窗口（通用/手势/外观/应用/关于）
│   ├── Services.swift         # 应用扫描、卸载相关文件、Dock 固定、全局热键、热角、捏合监听
│   └── PinchClassifier.swift  # 触控板多指手势判定
├── Tests/
│   ├── PanelTransitionProbe.swift # 完整面板开关、动画与构建一致性检查
│   ├── PanelAnimationProbe.swift # 内存中的动画与刷新率约定检查
│   ├── IdleResponsivenessProbe.swift # 隐藏窗口与输入线程隔离检查
│   ├── AlertPresentationProbe.swift # 全屏/窗口模式的弹窗层级与取消检查
│   ├── PinchGestureProbe.swift    # 手势识别与三指/四指面板路由检查
│   ├── TrayActivationProbe.swift  # 图标点击、轻微拖动与辅助功能按压
│   ├── TrayCornerProbe.swift      # 圆角外侧像素透明度检查
│   └── TrayPlacementProbe.swift   # 菜单栏下方 2px 间距与窗口层级检查
├── Resources/                 # 菜单栏图标
├── AppIcon.iconset/           # 应用图标源
├── AppIcon.icns
├── Info.plist
├── generate-icon.swift        # 生成应用图标与菜单栏图标
└── build.sh                   # 编译、组装、签名、校验
```

## 性能说明

- 隐藏面板移出显示列表并停用毛玻璃，保留视图和图标缓存。
- 完整启动面板保留从中心向外的四环图标出场，背景使用原生淡入淡出；仅当前页播放入场，同一环的图标一起合成。收纳面板在最终位置淡入，不跨过顶部菜单栏。
- 在支持的屏幕上请求优先 120 帧，刷新率偏好不会超过屏幕能力；60 Hz 屏幕最多只能显示 60 帧。
- 全局手势拦截使用独立运行循环，界面工作不会阻塞全局手势处理。
- 菜单栏应用在打开收纳面板及应用启动/退出时刷新，不做持续的定时扫描。
- 实际耗时与资源占用取决于系统、设备和应用数量，可使用以下探针检查当前构建。

## 测试

```bash
swift Tests/PanelTransitionProbe.swift <运行中的 Pinchpad PID> <源码根目录>

# 先打开收纳面板，再运行：
swift Tests/TrayCornerProbe.swift <运行中的 Pinchpad PID>
swift Tests/TrayPlacementProbe.swift <运行中的 Pinchpad PID>

# 应用必须已出现在收纳面板中；探针会实际点击并打开该应用：
swift Tests/TrayActivationProbe.swift <运行中的 Pinchpad PID> "<应用名称>" <bundleID> mouse

# 不需要触控板或运行中的应用，检查手势识别与面板路由：
swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Tests/PinchGestureProbe.swift -lsqlite3 \
  -o /tmp/PinchGestureProbe && /tmp/PinchGestureProbe

# 不发送系统输入、不读取个人应用库，检查方向键单次翻页与事件传递：
python3 Tests/PageNavigationProbe.py

# 不创建窗口、不依赖运行中的应用，检查动画与刷新率偏好：
swiftc Sources/IconEntrance.swift Sources/PanelAnimation.swift Tests/PanelAnimationProbe.swift \
  -o /tmp/PanelAnimationProbe && /tmp/PanelAnimationProbe

# 不发送系统输入、不显示窗口，检查输入线程与面板停用：
swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Sources/LauncherPanelVisibility.swift \
  Tests/IdleResponsivenessProbe.swift -lsqlite3 \
  -o /tmp/IdleResponsivenessProbe && /tmp/IdleResponsivenessProbe

# 原生确认框层级检查；测试只取消，不会删除任何内容：
swiftc -swift-version 5 Sources/PanelAlertPresenter.swift \
  Tests/AlertPresentationProbe.swift -o /tmp/AlertPresentationProbe \
  && /tmp/AlertPresentationProbe
```

探针覆盖：

- 原有波纹动画的时序与可见性、背景淡入端点、快速开关，以及 60/120/144/240 Hz 的刷新率偏好。内存检查不等同于实际显示帧率，后者需要在目标屏幕上实测。
- 构建一致性与完整启动面板的打开/关闭过渡。
- 收纳面板的圆角透明度、菜单栏下方 2px 间距、避开 Dock，以及图标是否能打开应用。
- 五档灵敏度、即时调整和旧设置迁移；三指/四指面板路由、系统「显示桌面」事件放行，以及系统左右/上下滑动的保留。
- 全屏/窗口模式下确认弹窗位于启动面板前方，且取消后面板仍然可见。

启动探针还支持 `drift`（轻微拖动）和 `ax`（辅助功能按压）模式。手势探针不安装设备监听，也不需要运行中的应用。弹窗探针只打开测试对话框并取消，不会删除任何内容。与实际应用交互的测试需要为终端或宿主程序授予相应的辅助功能、截屏及自动化权限。

## 常见问题

| 现象 | 处理 |
|---|---|
| 构建提示 `Quit the running Pinchpad before rebuilding...` | 先从菜单栏退出正在运行的 Pinchpad |
| 构建提示 `requires its original signing identity` / `Signing certificate does not match` | 签名目录丢失或被替换：恢复 `signing/` 目录，或同时删除 `Pinchpad.app` 和 `signing/` 后重新构建（会生成新身份，需要重新授予辅助功能） |
| 捏合手势不生效 | 在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Pinchpad；确认设置里对应的三/四指捏合已开启 |
| 四指张开不能显示桌面 | 在「系统设置 → 触控板 → 更多手势」中开启「显示桌面」，并使用已修复该手势拦截问题的新版 Pinchpad |
| 确认弹窗被启动面板遮挡 | 更新代码并重新构建；新版使用附属于面板的原生 sheet，不再依赖手动提高窗口层级 |
| 菜单栏区没有应用 | 授予 Pinchpad 辅助功能权限后重新打开面板；该区域只显示拥有菜单栏图标的第三方应用，不是所有运行中的应用 |
| 快捷键无反应 | 快捷键可能被系统或其他应用占用，设置里会给出提示，可更换组合键 |
| 首次打开稍慢 | 与登录后首次激活 app、初始化键盘焦点有关，是一次性开销 |
| 面板打开后图标位置/数量不对 | 设置 → 应用 → 重新扫描，或删除 `library.json` 恢复默认布局 |

## 卸载

1. 从菜单栏退出 Pinchpad。
2. 删除 `Pinchpad.app`。
3. 删除 `~/Library/Application Support/Pinchpad/`（设置、布局与签名身份都在这里）。
4. 在「系统设置 → 通用 → 登录项」与「隐私与安全性 → 辅助功能」中移除 Pinchpad。

## 许可证

本项目基于 **MIT License** 开源，详见 [LICENSE](LICENSE)。

Copyright (c) 2026 huangsz
