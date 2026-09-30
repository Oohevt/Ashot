# 进度
1. 目标：原生区域/窗口截图、四种可编辑标注、真实屏幕长截图，验收后才能完成。
2. 基线核对通过：仅研究文档；摘要符合任务书；Xcode 27 / Swift 6.4 / macOS 27 arm64。
3. 顺序：建立工程与独立验收答案并冻结 → 普通截图 → 编辑 → 长截图 → 实机验收。
4. 最大风险：权限授予、长截图歧义/丢帧、多屏坐标与编辑输入焦点。
5. 使用 SwiftPM 生成真实 .app；初始化根目录 Git，便于追踪；未引入外部依赖。
6. 任务 0：工程构建通过；3 个几何测试通过，0 跳过；oracle 自比对误差 0。
7. 独立坏图反向验证：入口返回 1，像素错误率 0.01637578125（上限 0.001）；原图入口返回 0。证据 evidence/task0/red.log、green.log。
8. 判据/入口/oracle/3 个测试/素材摘要已写入 acceptance.sha256；现在开始应用实现，尚无桌面功能验收。
9. 已实现普通区域/窗口采集、编辑器四类标注/撤销重做、快捷键配置和长截图流。首轮 9 个单元测试通过，冻结摘要全部符合，入口返回 0。
10. 已启动真实 `.app`，点击区域截图得到 TCC 拒绝错误。已向用户提示正常授权；当前桌面验收缺口保留，不判完成。
11. 后续修正窗口释放、快捷键 A（keyCode=0）持久化和独立队列所有权；新增异常/容量测试。完整验收尚未开始，3 轮止损计数 0。
12. 单执行者代码审查：深度审查，范围符合目标，桌面验收未完成。修复窗口移动与滚动混淆（绑定窗口本地采集）、导出失败保留会话、取消后迟到回调、窗口释放；渲染器移到可测试核心，新增像素/中文绘制测试。
13. 当前 17 个测试通过、0 跳过；最近验证 evidence/window-binding-verify.log。缺少真实截图权限，未完成9次长图、3类实机恢复及100次取消。
14. 当前构建 a72c6c4a9dfd48af，最终独立检查 evidence/current-green.log 返回0；反向检查 evidence/latest-red.log 返回1。详细状态 docs/TEST_REPORT.md，全部必需桌面门槛仍未验证，目标保持未完成。
15. 续跑发现运行日志中 09:22 已成功框选并进入编辑器，之前的权限阻塞说明过时；但旧实例的界面读取超时，进程采样显示正常事件等待（evidence/ashot-sample.txt），不能把读取超时当作应用崩溃。
16. 用户新增明确要求：快捷键改为 Option+W；普通/长截图完成自动复制，标注修改后更新剪贴板。正在实现并验证；保留原始验收门槛。
17. 新构建 b4a858a0835149c4：默认/首次迁移设置为Option+W，支持Option单修饰键和W；初始截图、标注提交、撤销/重做自动写PNG到剪贴板。2项新增测试使用真实命名NSPasteboard，不改用户通用剪贴板；总19测试通过，0跳过，日志 evidence/optw-final-verify.log。
18. 新增标准菜单、无窗口时重新打开主界面；长图接收器可变状态私有并限制在串行队列，编译无警告。旧运行实例仍为旧代码；待用户确认可以关闭未保存截图后，重启新构建继续实机验收。目标未完成。
19. 保留旧实例，启动同构建的新实例，新日志确认Option+W已注册（key=13、modifiers=2048）。用户随后退出旧实例并测试，但新构建出现TCC拒绝，且设置中开关已开启。
20. 签名根因已查实：原产物的designated requirement仅为cdhash，随构建改变，旧授权无法匹配。已找到本机现有Apple Development证书并成功签名；构建脚本改为固定证书身份。无新证书、无购买、无上传、未修改系统权限或TCC数据库；首次签名迁移仍需正常重新授权一次。
21. 用户明确允许经系统设置刷新Ashot授权，并本人完成“解锁”触控确认；当前“修改系统设置”仍需本人再次认证。已定位Ashot.app开关为on，等待认证后完成off→on同步。未处理密码/指纹。
22. 用户最新要求改为Option+A，覆盖之前Option+W。实际已保存key=0、modifier=2048；代码默认值/迁移修订2同步为Option+A，界面不再写死W；自动复制保留。
23. 通读全部源码后查出三处缺陷。最严重一处：Apple 文档明确 sourceRect 对单窗口采集无效（"The system doesn't reference this value when you capture a single window"），而长截图正是 desktopIndependentWindow + sourceRect，所以系统交付整个窗口再压扁到选区尺寸，选区从未生效。改为按窗口完整尺寸采集、每帧在接收器内用 Geometry.pixelRect 裁剪，裁剪比例由实际帧尺寸推导以免疫取整。
24. 第二处：SelectionView 是 isFlipped（y 自屏幕上边缘向下），SCWindow.frame/NSScreen.frame 是 CG 全局空间（y 自左下角向上），原实现直接把两者相加，等于取垂直镜像。新增 Geometry.globalRect/globalPoint 显式转换，容器取遮罩窗口实际所在的 snapshot.screen.frame；windowLocalRect 输出改为窗口左上角原点。第三处：拼接输出上下文硬编码 sRGB，会把 Display P3 采集降级。
25. 性能：StitchAccumulator 原先每接受一帧都把上一帧重新光栅化，并以 CGImage 持有上一帧（裁剪图会保留整个源帧后备存储）。改为缓存 Raster 并丢弃 CGImage 引用。
26. 冻结产物 Tests/AshotCoreTests/GeometryTests.swift 在 acceptance.sha256 第5行，本轮新增坐标测试改放独立 CoordinateTests.swift，冻结文件按字节还原，SHA-256 与记录一致；8 项冻结摘要全部 OK。未修改任何冻结判据、oracle 或验收说明。
27. 构建 86b9c34fdc2320c4：27 个测试（core 21 + app 6）全绿、0 跳过，verify.sh 返回 0，日志 evidence/coord-stitch-fix-verify.log；反向验证返回 1，错误率 0.01637578125 > 上限 0.001，日志 evidence/coord-stitch-fix-red.log。
28. 新测试做了反向验证以证明有鉴别力：退回旧坐标公式后 CoordinateTests 3 测试 5 断言失败（端到端裁剪位置由 (100,260) 变 (100,750)，垂直偏差 490 像素）；把色彩空间改回恒 nil 后 testWideGamutSourceSurvivesStrips 失败（实际 kCGColorSpaceSRGB，期望 kCGColorSpaceDisplayP3）。两处均已还原并重新全绿。
29. 权限阻塞根因查实（非猜测）：TCC 中 com.oohevt.Ashot 的 csreq 仅 40 字节，解码为 opcode 8 = opCDHash，钉住 ea837ef8a37fd3667e6feb3404b1b1aac2549a3b；当前构建 cdhash 为 5437ff9a80c048ebb6bcc53f804f7b1954f13e2e，不匹配。参照条目 com.oohevt.frameshot 为 164 字节完整指定要求。授权写入 17:55:04，证书签名实例启动 17:55:09，即用户授权的是旧 ad hoc 实例；此后 18:00/18:03/18:54/19:40 四次采集全被拒，该行 last_modified 始终停在 17:55:04，说明重建后从未重新授权。开关显示 on 是真的，但对应已不存在的二进制。
30. 解除旧实例顾虑：PID 84030 自启动后只有 4 次失败采集、0 次 overlayReady/editor，无未保存截图，已正常退出；改跑 PID 93373（构建 86b9c34fdc2320c4），日志确认 Option+A 注册、screenAccess=false。已为用户打开屏幕录制设置面板，等待其 off→on 重写 csreq；成功判据为 length(csreq) 变约 164。未代替用户操作权限，未修改 TCC 数据库。
31. 文档同步：TEST_REPORT.md 与 BLOCKED.md 中的 Option+W 全部更正为 Option+A；新增交付前必须移除 AshotWorkspaceRoot/AshotBuildID 注入的记录。完整桌面验收轮数仍为 0，止损计数 0，目标保持未完成。
32. 权限阻塞已实测解除。经用户批准执行 tccutil reset ScreenCapture com.oohevt.Ashot（条目 40→39，仅移除 Ashot），用户本人重新授权。新 csreq 为 160 字节、opcode 6 = opAnd，内含 com.oohevt.Ashot 与 Apple Development，不再是 40 字节的 cdhash 钉死（此前预测约 164，实际 160；决定性属性是 opcode 而非长度，故判为通过并如实记录偏差）。TCC 行 auth_value=2、auth_reason=4、last_modified=2026-09-29 20:28:55。
33. 决定性重建实验证明授权不再随构建丢失：构建由 86b9c34fdc2320c4（cdhash 5437ff9a…）重建为 af4785d080ef38f8（cdhash 2bd02fa88edc946d5e5958ebcdb9e080b1d0a8fd），TCC 行未被触碰（仍为 2|160|2026-09-29 20:28:55），新实例 PID 99700 日志 screenAccess=true、key=0、modifiers=2048。可执行文件 SHA-256 517f6a77e5042001b09d220b066bf2b24e23ef98f3c5f0f29ccb3112195001ce。恢复与诊断手段已写入 README：tccutil reset 重新授权；length(csreq) 40 = cdhash 钉死、160 左右 = 证书指定要求。
34. sourceRect 修复获得实机证据（evidence/runtime.jsonl，窗口 ego lite）：真实帧 3372×2100；选区 946×614 pt → 1892×1228 px，累计高度恰为 1228；选区 1462×692 pt → 2924×1384 px，累计高度恰为 1384。换算与真实帧比例吻合，选区路径已打通。但两次均以 longPaused「暂未对齐」结束——第一次一个像素未追加，第二次仅追加 12 像素，后者更像重复内容上的误匹配。当前缺每帧候选位移与误差遥测，无法区分「找不到」与「找错」，已列为 BLOCKED.md 头号阻塞，是 9 次长截图门槛的前置条件。
35. 新增用户要求的 W 键：框选后按 W 直接裁剪、写剪贴板、NSSound.beep()、关闭遮罩并把焦点交还前一应用，不进编辑器（iShot 同类行为）；Enter 或「编辑截图」仍进标注。改动限于 Sources/Ashot/Capture.swift 与 AppEntry.swift，遮罩提示与主界面说明已同步。verify.sh 返回 0、27 测试全绿（evidence/wkey-verify.log），但 runtime.jsonl 中 quickCopy 事件数为 0，即尚无真实按键证据。文档已同步至构建 af4785d080ef38f8；完整桌面验收轮数仍为 0，止损计数 0，目标保持未完成。
36. 新增设置页（用户要求；经确认目标为本项目而非第三方 iShot）。Sources/Ashot/Settings.swift + 设置窗口，三入口（状态栏菜单/⌘,/主界面按钮）；两个开关：不在 Dock 显示图标（UserDefaults + setActivationPolicy，启动即生效），开机时自动启动（SMAppService.mainApp 登录项，状态实时显示）。实机验证（computer-use 真实点击，构建 bb3081aaf7fa1561）：Dock 开→lsappinfo type 变 UIElement、关→回 Foreground，遥测双向往返；开机自启登记成功且 System Events 登录项列表出现 Ashot（与 iShot 并列）。换装新二进制（→6e78ed193138afd1，cdhash 变）后 loginItem 仍已启用、screenAccess 仍 true——登录项与屏幕权限均不随构建失效。已知：SMAppService.mainApp.status 首次登记前返回 .notFound（SDK 头文件注明为错误值），dist/ 与 /Applications 位置一致，登记不受影响；状态文案已如实改写。
37. 登录项指向 /Applications/Ashot.app，故 script/build_and_run.sh（非冻结）新增构建后同步：无实例运行时 ditto 到 /Applications，运行中则跳过。evidence/settings-verify-3.log 验证管线通过，两副本构建号一致（6e78ed193138afd1）、签名校验 OK。最终状态：运行实例即 /Applications 副本（PID 6937），launch 记录 ⌥A 注册、screenAccess=true、loginItem=已启用、hideDockIcon=false（已还原为默认显示）。文档 TEST_REPORT/README 已同步。quickCopy 实机证据仍缺；完整桌面验收轮数 0，止损计数 0，目标保持未完成。
38. 用户新增四项：① 截图分辨率核查（答复：已是物理原生分辨率，1920×1080 pt @2x 实采 3840×2160 px，selection 遥测已带 pixelWidth/pixelHeight；物理像素即上限，无法更高）；② ⌥A 遮罩左上角提示语删除（构建 f0dd73d9acd682ff）；③ 长截图「暂未对齐」诊断（见 39）；④ 「不在菜单栏显示」澄清为顶部菜单栏状态图标也要隐藏——hideAppIcon 开关改为同时隐藏 Dock（accessory 策略）与状态栏图标（status.isVisible），开关文案与警示更新（构建 f0dd73d9acd682ff）。
39. 长截图对齐根因查实并修复。新增 MatchReport 每帧遥测（same/best/runnerUp 位移与误差、verify、结局）由 LongReceiver 以 longFrame 落盘；夹具复现抓到实锤：bestShift=51、bestError=0（完美对齐）被 runnerError=0.0167 的周期性近似匹配按旧「差值<0.03」歧义规则否决——静态重复文本每帧必被误拒，与滚动快慢无关。修复：歧义要求第二名自身 ≤ acceptError(0.008)，真歧义（两个可行命中）仍拒绝。修复后同流程端到端复现：连续 4 帧追加（1140→1343 px，各帧 runnerError 0.017–0.023 在旧规则下全会被拒）、结束出图 880×1343 进编辑器。历史 4 次「暂未对齐」均在 ego lite/Qoder CN 动态内容上 0–3 秒内触发，属设计拒绝（testLargeDynamicChangeRejected 钉死），不放宽。27 测试全绿、verify.sh=0（evidence/matcher-fix-verify.log）。
40. 菜单栏图标隐藏实机验证（构建 017bb9c6924347eb，AXPress 触发开关）：开→遥测 hidden:true、lsappinfo type=UIElement、NSStatusItem VisibleCC Item-0 由 1→0、菜单栏右上像素差 1.02%；关→三项全部还原。诊断插曲：本机 Mac Mouse Fix Helper 曾于 12:39-12:40 崩溃 3 次、WindowManager 的 Gesture Blocking Overlay 会把合成拖拽当成吸边手势（夹具窗口两次被吸成 53×100 小块，AppleScript set size/position 可恢复）；computer-use SDK 对 "Ashot" 名字会误解析到 AshotFixture，须用 bundle id，SwiftUI 开关用 AXPress 最稳。文档三件套已同步至 017bb9c6924347eb。
41. 清晰度诊断：W 键实机证据到手（400×540 pt → quickCopy 800×1080 px，剪贴板 PNG 吻合）；同区域与系统 screencapture 逐像素主体一致（平均差 0.64/255），差异仅夹具滚动条淡出的 64 行——采集为原生 2 倍像素。真凶：Ashot PNG 无 DPI 元数据（72）而系统为 144，粘贴端按两倍逻辑尺寸缩回导致重采样变糊；修复方向（pHYs 元数据）已写入 TEST_REPORT 待用户确认后实施。
42. ⌘W 修复（用户报告）：菜单缺「文件 → 关闭窗口」标准项，补 performClose: 后（构建 843aa17d278ffa4c）实机验证主窗口/设置窗口均可 ⌘W 关闭；长截图面板不带 closable 故不受影响（有意，避免绕过清理逻辑）。排查中发现 dist 与 /Applications 双实例并存曾互相干扰测试（kill 双实例后单实例复测）。另有残留 dist/AshotQA.app 经用户确认删除（无任何引用）。DPI 修复仍未实施；完整桌面验收轮数 0，止损计数 0，目标保持未完成。
43. 用户要求检查当前已完成软件：复跑 verify.sh，27测试全绿、0跳过、冻结摘要及签名校验通过。实际普通截图200×120pt→400×240px，W复制/退出、系统预览剪贴板导入通过；发现P1长截图坐标仍混用（同窗AppKit y286、SCK y126；实际选区711,155,498,638转换为y287后误报longNoTarget），以及P2缺DPI/P2标注宽色域转sRGB。详见docs/REVIEW_REPORT.md。只增强测试查看器的复位/坐标采样，未改产品实现；不能据此标记完整验收完成。
44. 用户授权修复上述三项。统一SCDisplay/SCWindow左上坐标并锁定截图时目标；CapturedImage携带每轴像素倍率，经裁剪、编辑、撤销重做与长图传至PNG/剪贴板DPI；标注与拼接共用源RGB色彩空间。旧逻辑回归红灯，修复后Core23+App14共37项全绿、0跳过，最终日志evidence/three-fixes-cooperative-focus-verify.log，8项冻结摘要不变。真实200×120pt框选经W得到400×240px/144DPI，NSImage解码200×120pt，证据three-fixes-live-retina.png。P3独立探针及未标注像素检查通过。
45. 最终构建1f7f19faafc49164已同步并启动/Applications副本，两个可执行文件摘要相同，签名通过；Option+A、screenAccess=true、隐藏图标及登录项设置保留。实机长图选区已正确启动，早一版收到1276px首帧；补充协作激活与后台缩略图监测处理后，最终版本本轮自动操作仍停在0px/0帧，已取消并恢复入口，根因未定。不能宣称连续拼接或第一阶段完整验收通过。修复边界与证据详见docs/THREE_FIXES_REPORT.md。
46. 实机0帧追到系统日志frameStatus=4（suspended）、目标缩略窗口；开始长图时收起Ashot主窗口后恢复采集。最终构建5f40dc489aef4cc9，37项测试全绿、0跳过，evidence/three-fixes-final-window-verify.log。贴边选区3帧1276→1468→1660，958×1660出图自动复制；贴边全图Oracle比对1.0528%失败，差异集中右侧11px/左下圆角，保留原证据。重新实际选取纯内容730,156,440,618，3帧1236→1428→1620，880×1620出图、144DPI、逻辑440×810pt；冻结Oracle比对全部1425600像素0处超出容差、返回0。三项修复针对性验收完成；9次完整长图等总体门槛仍未跑满。最后退出测试编辑器并同步安装两副本，SHA-256均4be90ea65419cd039edf8c105c38fb4d8f1a8fa0059992c4ac27c12b6f4bd16e，签名/冻结摘要通过；Option+A、权限和图标/登录项偏好保留。
