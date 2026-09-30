# 第一阶段验证记录 · 未完成

日期：2026-09-29。当前产物 `dist/Ashot.app`，部署目标 macOS 14；测试机器 macOS 27 / Apple Silicon。

当前构建标识：`5f40dc489aef4cc9`。
应用可执行文件 SHA-256：`4be90ea65419cd039edf8c105c38fb4d8f1a8fa0059992c4ac27c12b6f4bd16e`。
CDHash：`937214c01edfe468aca80e1459f30673ef6ab531`。
签名：`Apple Development: oohevt@qq.com (GAP2S4TS2U)`，TeamID `AGBKX8332D`。未公证、未发布。
当前运行实例为 `/Applications/Ashot.app`（PID 42822），`screenAccess=true`、`loginItem=已启用`、`hideAppIcon=true`。

用户要求：快捷键默认/首次迁移为 `⌥ A`；截图与标注变更后自动更新剪贴板；框选后按 `W` 直接复制并关闭、不进编辑器；设置页含「不显示应用图标（Dock 和顶部菜单栏）」与「开机时自动启动」；遮罩左上角提示语删除。以上均已实现；遮罩提示语删除、菜单栏图标隐藏已随本轮构建进入验证。

## 三项审查问题修复（最新）

最终构建37项测试（Core23+App14）全部通过，0失败、0跳过；签名与8项冻结摘要通过。真实Retina截图200×120pt导出400×240px/144DPI，解码保持200×120pt；Display P3标注后色彩空间及未标注像素保持。长图坐标误报已消除；收起Ashot主窗口解决本轮流被暂停的问题，两次局部长图实际滚动拼接、进编辑器与自动复制通过。纯内容880×1620px产物经冻结Oracle比对通过（0处超出容差）。完整证据见[三项修复记录](THREE_FIXES_REPORT.md)。

## 早先修复记录（历史）

下列第2项Y轴假设已被本次实机审查纠正：SCWindow.frame属于左上原点坐标，NSScreen.frame为AppKit左下原点，不能混用；当前全局换算使用SCDisplay.frame，仅平移，不做Y翻转。

代码审查发现三处缺陷，其中第一处使长截图选区从未真正生效。

1. **`sourceRect` 对单窗口采集无效。** Apple 文档对 `SCStreamConfiguration.sourceRect` 明确写着：“The system doesn’t reference this value when you capture a single window because it captures the full bounds of the window.” 原实现用 `SCContentFilter(desktopIndependentWindow:)` 又设置 `sourceRect`，因此系统交付的是**整个窗口**，再被 `config.width/height`（按选区尺寸设置）压扁。用户看到的长截图既包含窗口边框和无关区域，比例也是错的。改为：按窗口完整尺寸采集，每帧在 `LongReceiver` 内用 `Geometry.pixelRect` 裁出选区。裁剪比例由实际帧尺寸推导，不受取整和缩放影响。
2. **Y 轴翻转。** `SelectionView` 是 `isFlipped = true`（y 自屏幕上边缘向下），而 `SCWindow.frame` 与 `NSScreen.frame` 属 Core Graphics 全局空间（y 自主屏左下角向上）。原实现把 `rect.midY` 直接加到 `display.frame.minY` 上，等于取垂直镜像位置。新增 `Geometry.globalRect(_:in:)` 与 `Geometry.globalPoint(_:in:)` 做显式转换，容器取 `snapshot.screen.frame`（即遮罩窗口实际所在的矩形）。同时 `Geometry.windowLocalRect` 的输出改为**窗口左上角原点**，与 ScreenCaptureKit 帧和 `CGImage.cropping` 的空间一致。
3. **拼接性能与色彩。** `StitchAccumulator` 原先每接受一帧都把上一帧重新光栅化一次（`Raster(previous)`），且以 `CGImage` 形式持有上一帧，而裁剪产生的 `CGImage` 会保留整个源帧的后备存储。改为缓存 `Raster` 并丢弃 `CGImage` 引用。输出上下文原先硬编码 sRGB，会把 Display P3 采集降级；改为沿用源图色彩空间，创建失败时回退 sRGB。比对用的 `Raster` 仍归一化到 sRGB，保证跨帧可比。

## 权限阻塞已解除（实测确认）

原阻塞的根因已查实，不是猜测：`/Library/Application Support/com.apple.TCC/TCC.db` 中 `kTCCServiceScreenCapture` / `com.oohevt.Ashot` 一条曾是 `auth_value=2`（已允许）、`auth_reason=4`（用户设置）、`last_modified=2026-09-29 17:55:04`、`length(csreq)=40`。

解码那 40 字节 csreq：magic `0xfade0c00`、length 40、version 1、**opcode 8 = `opCDHash`**、hash 长度 20、钉住的哈希 `ea837ef8a37fd3667e6feb3404b1b1aac2549a3b`。对照正常参照条目 `com.oohevt.frameshot` 为完整指定要求。只有 40 字节说明 TCC 记录时看到的是一个 **ad hoc 签名**进程，只能按 cdhash 钉死。

时间线也吻合：授权写入 `17:55:04`，而证书签名实例启动于 `17:55:09`。用户授权的是旧实例；5 秒后启动的证书签名实例 cdhash 不同，TCC 判定不匹配并拒绝。此后 18:00、18:03、18:54、19:40 四次采集全部被拒，而该行 `last_modified` 始终停在 `17:55:04`，说明重新构建之后**从未重新授权过**。系统设置里开关显示为 on 是真实的，但它对应的是一个已不存在的二进制，因此无论点多少次都无效。

处置（每一步都经用户明确同意）：先确认旧实例 PID 84030 只有 4 次失败采集、0 次 `overlayReady`/`editor` 事件，即无未保存截图，随后正常退出；经用户批准执行 `tccutil reset ScreenCapture com.oohevt.Ashot`（条目数 40→39，仅移除 Ashot 一行），启动证书签名构建，由用户本人在系统设置重新授权。未代替用户操作权限，未直接修改 TCC 数据库。

**实测确认修复成立：**

| 核对项 | 结果 |
|---|---|
| 新 csreq | `length(csreq)=160`，opcode 6 = `opAnd`，内含 `com.oohevt.Ashot` 与 `Apple Development`（不再是 cdhash 钉死） |
| TCC 行 | `auth_value=2`、`auth_reason=4`、`last_modified=2026-09-29 20:28:55` |
| 决定性重建实验 | 构建由 `86b9c34fdc2320c4`（cdhash `5437ff9a…`）重建为 `af4785d080ef38f8`（cdhash `2bd02fa8…`），TCC 行**未被触碰**，仍是 `2\|160\|2026-09-29 20:28:55` |
| 重建后运行日志 | 新实例 `screenAccess: true`，`⌥ A` 已注册，采集不再被拒 |

结论：授权现绑定证书指定要求而非某次构建的 cdhash，**重新构建不再掉授权**。日后若再出现同类症状，恢复手段是 `tccutil reset ScreenCapture com.oohevt.Ashot` 后重新授权；诊断手段是看 `length(csreq)`，40 = 被 cdhash 钉死，160 左右 = 证书指定要求。

## 已有真实命令证据

1. `./scripts/verify.sh` 返回 0；最近日志 `evidence/matcher-fix-verify.log`（歧义修复后）：AshotCoreTests 21 个、AshotAppTests 6 个，共 27 个 XCTest 测试，0 失败，0 跳过。Swift Testing 的额外“0 tests”行是未使用该框架，不代替 XCTest 计数。
2. 冻结摘要 8 项全部 OK（研究文档、验收说明、验证入口、独立 oracle、初始几何测试、3 张素材）。`Tests/AshotCoreTests/GeometryTests.swift` 是冻结产物，本轮新增坐标测试放在独立的 `CoordinateTests.swift`，冻结文件按字节还原，SHA-256 与 `acceptance.sha256` 第 5 行一致。
3. 反向验证 `./scripts/verify.sh evidence/task0/corrupt.png fixtures/article.png` 返回 1，日志 `evidence/coord-stitch-fix-red.log`：错误像素比例 0.01637578125，大于冻结上限 0.001。oracle 与判据未改变；独立自比对 `mismatch=0`。
4. **新测试的反向验证**（证明测试有鉴别力，不是恒真）：
   - 把 `Geometry.globalRect/globalPoint` 临时退回旧公式后，`CoordinateTests` 3 个测试 5 处断言失败。端到端裁剪位置由正确的 `(100, 260)` 变为 `(100, 750)`，垂直偏差 490 像素。
   - 把 `StitchContext.space(of:)` 临时改为恒返回 `nil`（即退回硬编码 sRGB）后，`testWideGamutSourceSurvivesStrips` 失败：实际 `kCGColorSpaceSRGB`，期望 `kCGColorSpaceDisplayP3`。
   - 两处均已还原，还原后完整套件重新全绿。
5. **`sourceRect` 修复的实机证据**（`evidence/runtime.jsonl`，构建 `86b9c34fdc2320c4`，目标窗口 `ego lite`）：真实帧尺寸 `3372×2100`；第一次选区 `946×614` pt 换算为 `1892×1228` px，累计高度恰为 **1228**；第二次选区 `1462×692` pt 换算为 `2924×1384` px，累计高度恰为 **1384**。换算与真实帧比例完全吻合，证明选区路径已打通。修复前这两次得到的都会是被压扁的整窗图像。
6. 自动复制验证使用真实独立命名 `NSPasteboard`，确认初始化后 PNG 尺寸/像素，以及标注、撤销和重做自动改变 PNG；不触碰用户通用剪贴板。这仍不能代替外部应用粘贴验收。

## 长截图对齐失败：根因已查实并修复（本轮）

给 `VerticalMatcher` 加了每帧诊断（`MatchReport`：same/best/runnerUp 的位移与误差、dense verify 结果、结局），由 `LongReceiver` 以 `longFrame` 事件写入 `evidence/runtime.jsonl`。随后在 AshotFixture（500×668 文章滚动视图）上真实滚动复现失败。

**根因（数据实锤，非猜测）**：复现帧 `bestShift=51, bestError=0`（完美对齐），`runnerShift=307, runnerError=0.0167`。旧歧义规则是「第二名与最佳误差差值 < 0.03 即拒绝」，于是完美匹配被一个远差于阈值的周期性近似匹配否决——重复文本行距会产生周期性近似命中，静态文章内容**每一帧都会被误拒**。与滚动快慢无关。用户历史 `longPaused` 里的「内容重复，无法确认拼接位置」即此分支。

**修复**：歧义判定改为「第二名自身必须也是可行匹配」（`runnerUp.error ≤ acceptError`）。两个可行命中彼此差值必然小于原 0.03 边距，真歧义仍拒绝；不可行的第二名不再一票否决。`acceptError=0.008` 提为具名常量。

**修复后端到端复现**（构建 `017bb9c6924347eb`，同夹具同滚动方式）：连续 4 帧追加（shift 51/50/51/51，`bestError=0`、`verify=0`，第二名误差 0.017–0.023——每一帧在旧规则下都会被拒），累计 1140 → 1343 px，「结束并编辑」出图 880×1343 并进入编辑器，`longFinish` 记录在案。27 测试全绿、`verify.sh` 返回 0（`evidence/matcher-fix-verify.log`）。

**另一分支「暂未对齐」（unaligned）定性为设计行为**：历史 4 次全部发生在 `ego lite`/`Qoder CN`（流式聊天、闪烁光标等动态内容），且都在启动后 0–3 秒、用户尚未滚动时触发——第二帧与第一帧存在任何位移都无法对齐的动态差异。单元测试 `testLargeDynamicChangeRejected` 早已钉死「动态改变拒绝」，提示文案也明确列出「出现动态内容」。此分支不应放宽（放宽即接错图），用户侧的规避是等动态内容静止后再长截图。

## W 键直接复制（已实现，已有实机证据）

框选后按 `W`：裁剪选区 → 写入剪贴板 → `NSSound.beep()` → 关闭遮罩 → 焦点交还前一应用，**不打开编辑器**。按 `Enter` 或点「编辑截图」仍进标注。

实机证据（构建 `017bb9c6924347eb`，2026-09-29）：⌥A 框选 400×540 pt → `quickCopy` 事件记录 800×1080 px，剪贴板 PNG 尺寸吻合（2 倍原生）。

## ⌘W 关闭窗口（已修复）

`buildMainMenu()` 原先只有应用菜单与「编辑」菜单，缺少「文件 → 关闭窗口 ⌘W」标准菜单项，因此 ⌘W 对所有窗口无效（红色关闭按钮不受影响，窗口本身带 closable）。构建 `843aa17d278ffa4c` 补上该项（`performClose:`，无 target 走响应链到关键窗口）。实机验证：主窗口 ⌘W 关闭（1→0）；激活后 ⌘, 打开设置（0→1）、⌘W 关闭（1→0）。长截图面板不带 closable，`performClose:` 按文档定义对其无效，仍只能用面板按钮——这是有意保持的（避免绕过采集清理逻辑）。

## PNG DPI 元数据缺失（已修复）

最新实现随文档传递实际像素倍率，保存和剪贴板写每轴DPI；1×、2×、分轴倍率、编辑/撤销/重做与长图倍率回归均通过。实机200×120pt截图为400×240px/144DPI，解码仍为200×120pt。

以下保留修复前诊断：同一区域实测对比：Ashot 剪贴板 PNG 与系统 `screencapture` 同为 800×1080 px、逐像素主体一致（平均差 0.64/255，差异集中在夹具滚动条淡出的 64 行），但系统 PNG 带 144 dpi（2 倍屏标识），Ashot 的 PNG 无 DPI 元数据（默认按 72 dpi）。粘贴到按逻辑尺寸排版的 App 时被当成两倍大、再被缩回 → 重采样即用户感知的「糊」。修复方向：导出时按采集缩放系数写入 pHYs。微信聊天自身还会再压图，属目标应用行为。

## 设置页（已实现，已有实机证据）

新增 `Sources/Ashot/Settings.swift` 与设置窗口（入口三处：状态栏菜单「设置…」、应用菜单 `⌘ ,`、主界面「设置…」按钮），含两个开关：

1. **不显示应用图标（Dock 和顶部菜单栏）。** 存 `UserDefaults`（`hideAppIcon`，经用户确认后取代早先仅 Dock 的 `hideDockIcon`）：Dock 用 `setActivationPolicy(.accessory/.regular)`，菜单栏状态图标用 `status.isVisible`，启动即生效。开启后唯一入口是截图快捷键，界面附此警示。
2. **开机时自动启动。** 用 `SMAppService.mainApp` 登记/取消登录项，状态文本实时显示（已启用 / 未登记 / 待批准 / 查询失败）。

Dock 开关实机证据（构建 `bb3081aaf7fa1561`，computer-use 真实点击）：开→遥测 `settingDockIcon hidden:true`、`lsappinfo` 由 `Foreground` 变 `UIElement`；关→反向还原。开机自启：遥测 `status:已启用`，`System Events` 登录项列表出现 `Ashot`；换装新二进制（cdhash 改变）后仍「已启用」——登录项与屏幕权限都不随构建失效。

**菜单栏图标隐藏实机证据（构建 `017bb9c6924347eb`，AXPress 真实触发设置开关）**：

| 动作 | 证据 |
|---|---|
| 开启 | 遥测 `settingHideIcon hidden:true`；`lsappinfo` `type="UIElement"`；AppKit 自身的状态项存档 `NSStatusItem VisibleCC Item-0` 由 1 变 0；菜单栏右上 360×30 pt 截图像素差 1.02%（约一个图标面积） |
| 关闭 | 遥测 `settingHideIcon hidden:false`；`hideAppIcon=0`；`NSStatusItem VisibleCC Item-0` 回 1；`lsappinfo` 回 `type="Foreground"`（像素对比含时钟走动的正常残差 ~1%） |

已知事实：`SMAppService.mainApp.status` 在**首次登记前**返回 `.notFound`（SDK 头文件定义："An error occurred and no such service could be found"，是错误值而非位置问题）；登记本身不受影响。

配套改动：登录项指向 `/Applications/Ashot.app`，因此 `script/build_and_run.sh` 在构建后、无实例运行时自动 `ditto` 同步该副本（有实例在跑则跳过）。该脚本不在冻结清单内。

## 测试覆盖

- 点/像素转换、边界裁切和非法区域（冻结）。
- 选区到SCDisplay全局空间的平移、副屏偏移、窗口本地左上原点、选区到裁剪矩形的端到端换算及实测窗口坐标回放。
- 全窗口帧中按选区裁剪的位置正确性、垂直镜像的反向对照、随实际帧缩放、退化裁剪拒绝。
- 标注撤销重做分支、移动保留尺寸。
- 原图无标注时不变；不透明遮盖的左上坐标、矩形/箭头输出、中文文字实际绘制。
- 长图已知位移完整重建（所有像素一致）、重复帧不追加、无重叠保留已有结果、横移拒绝、动态改变拒绝、尺寸变化与容量拒绝、Display P3 经拼接后色彩空间保持。

算法测试使用固定图像，仅证明该算法路径；不能证明 ScreenCaptureKit 真实采集、窗口焦点或目标应用粘贴。**特别是：`sourceRect` 失效这一缺陷正是单元测试无法发现、只能靠查文档发现的类型**，因此长截图的 9 次实机验收不可省略。

## 仍未通过的完成门槛

| 项目 | 当前证据 |
|---|---|
| 屏幕录制授权对新构建生效 | **已通过**：csreq 160 字节 / opAnd，重建后 TCC 行未变且 `screenAccess=true` |
| 普通区域/窗口截图及保存重开 | 权限已通，尚未实机跑一遍 |
| 从真实截图进入编辑器，4 类标注操作与保存/复制 | 未验证 |
| 复制后粘贴到真实外部应用 | 旧版本PNG已实际导入系统预览；新版本DPI与NSImage解码尺寸通过，目标应用粘贴显示尚未重测 |
| 按 W 直接复制并关闭（框选后） | **已通过实机验证**（quickCopy 800×1080） |
| 设置页：图标开关（Dock+菜单栏）、开机自启 | **已通过实机验证**（含重构建耐受）；「重启后自动拉起」属系统行为，未单独验证 |
| 文章/表格/代码各连续 3 次长截图，共 9 次 | 未验证；对齐根因已修复且夹具端到端通过，待按验收脚本跑满 9 次 |
| 失去重叠、动态干扰、目标变化的实机恢复 | 未验证 |
| 100 次实机触发/取消与内存记录 | 未验证；本轮减少了每帧一次全尺寸光栅化，内存曲线需重新记录 |
| 最低支持版本、多屏 | 缺少相应机器，未验证 |
| 交付前移除 `AshotWorkspaceRoot` / `AshotBuildID` 注入 | 未处理；运行日志取证依赖前者，故暂时保留 |

应用实现已进入验证阶段，尚不能标记第一阶段完成。完整桌面验收轮数为 0。

## 续跑位置

最新修复记录以THREE_FIXES_REPORT.md为准。两次局部长图与纯内容像素比对已通过，接下来仍需跑满完整验收。下一步：

1. 用户实机按 `⌥ A` → 框选 → 按 `W`，确认提示音、遮罩关闭、焦点回到前一应用、剪贴板得到 PNG；随后核对 `evidence/runtime.jsonl` 出现 `quickCopy` 事件。
2. 用户在 `ego lite` 等含动态内容的应用上重试长截图：若 AI 回复已流式完成、页面静止，歧义修复后应可正常追加；若仍暂停，`longFrame` 遥测已能区分「找不到」（bestError 高）与「找错」（runner-up 干扰）。
3. 按冻结的 `docs/ACCEPTANCE.md` 跑完整桌面验收（含 9 次长截图、3 类恢复、外部粘贴、100 次触发/取消）。任何失败修复后重跑受影响项；最多 3 轮完整验收修复仍不通过时保持未完成。当前止损计数 0。
