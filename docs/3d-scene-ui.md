# 3D 场景内 UI（feat/3d-scene-ui）

把游戏界面从「铺在 2D 视图上的叠加层」改造为「放进三维场景里」，对应任务要求：

1. **全 3D，不平铺到视图上** —— 字幕、事件标记、声纹都存在于三维世界，随相机移动而具有空间位置与遮挡关系。
2. **可被观察到的事件 → 可点击收集的小球** —— 每条课堂事件在触发位置生成一颗发光小球（`EventOrb3D`），玩家用鼠标左键点击即可收集（收集后缩小上浮并消失）。
3. **说话字幕直接在说话者旁边出现** —— 说话时，3D 标签悬浮在对应说话者头部附近并始终朝向相机（`SceneUI3D` 复用 `DialogueFlow` 已有的说话者锚点）。
4. **发出动静的地方有声纹** —— 台词播放、教师走位、人物动作剪辑时，在该处生成向外扩散的环形声纹（`SoundRipple3D`，用 TorusMesh + StandardMaterial3D 纯几何实现，零自定义着色器）。

## 接入方式（不改动流程时序）

- `DialogueFlow` 新增两个信号：`event_observed(event_id, label, world_position)`（在 `_fire_event` 发出，位置优先取事件的 `camera.look` 机位目标，其次取事件相关演员节点，最后回退到教师）与 `sound_emitted(world_position, intensity)`（在播放台词/音效、教师走位、人物动作剪辑时发出）。
- `DialogueUI` 新增两个信号：`world_subtitle(speaker_key, display, text)` 与 `world_subtitle_cleared`，由 `DialogueFlow._show_segment` / `DialogueUI.clear_subtitle` 发出。
- `SceneUI3D`（新增 `Node3D`）挂在 `scenes/classroom_dialogue.tscn` 下，连接上述信号并生成 3D 元素。

## 如何开启

- 触发 3D 字幕：将 `DialogueUI` 节点的导出项 `flat_subtitle` 设为 `false`，即可隐藏原来铺在底部的 2D 字幕条，只保留说话者旁边的 3D 字幕（`classroom_dialogue.tscn` 中已默认设为 `false`）。
- 不改动该选项时，2D 字幕条与 3D 字幕并存，便于对照验收。

## 已知边界 / 待人工验收

- 说话者「旁白（stage）」没有明确的世界锚点，默认落到讲台附近；如希望旁白出现在教室中心，可在场景里加一个 `Marker3D` 并接到 `SceneUI3D.stage_anchor`。
- 3D 字幕 / 标签的文字清晰度依赖 `Label3D.pixel_size` 与相机距离，需人工在编辑器里按实际观感微调。
- 声纹采用 TorusMesh + StandardMaterial3D（内置几何与材质，零自定义着色器），完全兼容 GL Compatibility 渲染器，规避自定义 ShaderMaterial 在部分后端的运行时崩溃风险。
- 点击收集依赖视口的三维拾取（默认开启）；若日后关闭需在项目设置里确认 `physics/3d/ray_picking`。
- 画面改动需由人在编辑器里实际试玩验收（自动测试不能替代完整流程与情绪强度判断）。

## 文件清单

- `scripts/scene_ui_3d.gd`（新增）3D UI 管理器
- `scripts/event_orb_3d.gd`（新增）可收集事件小球
- `scripts/sound_ripple_3d.gd`（新增）声纹（TorusMesh + StandardMaterial3D 纯几何实现）
- `scripts/dialogue_ui.gd`（改动）新增 world 信号、导出 `flat_subtitle`
- `scripts/dialogue_flow.gd`（改动）新增 `event_observed` / `sound_emitted` 信号并在对应处发出
- `scenes/classroom_dialogue.tscn`（改动）挂入 `WorldUI` 并接好锚点、`DialogueUI.flat_subtitle=false`

## 修复记录（2026-10-30）：运行数秒后卡死/闪退

**病因**：`SceneUI3D` 的 3D 字幕、`EventOrb3D` 的标签、以及 `SoundRipple3D` 原本都用 `look_at(相机位置)` 让它们面向相机。当相机平移到说话者/事件锚点所在位置（对话里 `board_teacher` / `left_neighbor` / `laugh_seat` / `dissent_seat` / `self_head` 等机位正是这些坐标）时，`look_at` 的注视方向长度趋近于 0，算出退化的 NaN 变换矩阵，使渲染/可视服务器崩溃。

**修复**：改用安全的公告板朝向——
- 两类 `Label3D`（字幕、小球标签）改用内置 `Label3D.BILLBOARD_FIXED_Y`（仅绕 Y 轴、保持直立，Godot 内部已规避退化方向）。
- `SoundRipple3D` 改为仅绕 Y 轴偏航面向相机，并在水平距离 ≈ 0 时跳过，永不产生 NaN。
- `SceneUI3D._spawn_ripple` 增加并发上限（≤24）作为防御。

三个功能（小球 / 3D 字幕 / 声纹）均保留。

## 修复记录（2026-10-30）：编译报错 + 仍闪退

**二修 · 枚举名写错（Parser Error）**：误用 `Label3D.BILLBOARD_FIXED_Y`，该枚举属于 `BaseMaterial3D`。已改为 `BaseMaterial3D.BILLBOARD_FIXED_Y`。

**三修 · PR 冲突**：`feat/3d-scene-ui-fix` 对 `main` 在 GitHub 上出现 2 文件冲突（同一行 main 为错误枚举、分支为正确枚举）。已本地 rebase 到最新 `origin/main` 并保留正确版本，强推后 PR 无冲突。

**四修 · 运行时仍闪退（本次）**：截图显示为项目原有文件的 `SHADOWED_VARIABLE_BASE_CLASS` 黄色警告（非致命、非我代码、不导致闪退），真正的闪退最大嫌疑是声纹所用的**自定义着色器 `ring_expand.gdshader`**（GL Compatibility 下自定义 ShaderMaterial 最易在声纹密集出现时运行时崩溃）。已把 `SoundRipple3D` 改为**纯几何实现**：`TorusMesh`（内置图元）+ `StandardMaterial3D`（unshaded / alpha 透明 / billboard），`_process` 中放大并淡出，零自定义着色器、零 NaN 风险。原 `shaders/ring_expand.gdshader` 因不再被引用已删除。三个功能均保留。

> 注：本机无 Godot，以上为基于代码的最高概率定位，仍需在 Godot 中 F6 跑 `classroom_dialogue.tscn` 实测验收。若仍运行时崩溃（非编译错误），则需在 Godot 调试器「错误」页抓取红色致命错误文本再定位。

## 重做记录（2026-10-31）：视觉与交互

- `DialogueUI`：控件改在 `SubViewport` 中排版，按控制条 / 回答框 / 卡片 / 词条 / 提示分别采样到相机前的世界空间 `Sprite3D`；用相机射线把鼠标坐标映射回控件，保留中文输入与键盘焦点。
- `SceneUI3D`：字幕改为带底板的分行 `Sprite3D`，按说话人分配锚点高度与文字尺度；字幕 `render_priority=10` 且不做深度测试，保证不被前排人物挡住。
- `EventOrb3D`：发光球体改为观察符号 + 短标签，悬停展开完整事件名；按相机距离缩放，近距离标签上移，避免贴脸或掉出画面。类名沿用 `EventOrb3D`。
- `SoundRipple3D`：粗 `TorusMesh` 改为三段断续细弧（`ImmediateMesh`），更小、更淡；声源贴近相机时不生成，防止满屏弧线。
- 新增素材：`assets/ui/observe_marker.svg`、`assets/ui/observation_tag.svg`。
- 验证：`tests/dialogue_check.gd` 通过（含 8 个坐标视野与间距、真实世界面板点击）；`tests/dialogue_capture.gd` 产出 13 张画面，已人工查看开场、卡片、字幕、标记与回答框。

## 修复记录（2026-11-07）：字幕压住老师

**现象**：老师站在讲台后（`podium_position` = `(-0.2, 0.15, -2.8)`），台词字幕按「锚点 + 1.75 m」居中摆放，面板中心只有 1.90 m；老师网格顶部实测 2.006 m，于是一行字幕（约 0.49 m 高）压住额头与鼻子。旁白（stage）锚点更低（1.50 m），整块框直接把老师整个人盖住。字幕 `no_depth_test = true`，遮挡是无条件的。

**修复**：
- `SceneUI3D` 新增 `_head_height()`：用网格包围盒实测说话者头顶相对其根节点的高度（老师 1.8556 m），结果缓存在 `_head_height_cache`；拿不到网格时退回导出项 `subtitle_height`。
- 字幕改成「底边贴着说话者头顶」摆放：`pos.y = 锚点 + 头顶高度 + subtitle_head_gap(0.16) + 面板半高`。行数变化只向上长，长句不会往下压脸；行高常量换了也不用同步改这里。
- 旁白（stage）同样按底边计算，`StageAnchor` 从 `(-1.0, 1.5, -2.2)` 抬到 `(-1.05, 2.18, -2.2)`：旁白框浮在讲台上方，不再整块盖住老师。
- 验证：`tests/dialogue_check.gd` 通过；`tests/dialogue_capture.gd` 全流程 19 张截图无异常；另用临时脚本量过屏幕坐标——老师头顶与字幕底间隙约 36 px，4 行旁白顶边 y≈115（顶部控制条底 88，不重叠）。

## 观察人物与头部点击（2026-11-07）

- 第一层的 8 个观察事件通过内容中的 `observation_actor` 绑定已有同学；`orb_position` 保留为第二层思绪的事件落点。课堂编号、触发点和时序未改动。
- 相关人物使用独立的材质覆盖层显示整个人物变暗再复原的闪烁，2.4 秒一轮，最暗时覆盖 72% 黑色，恢复时完全露出原色与光照；不修改模型原材质。头部四角框、拾取球共用原点，实时跟随 Head 骨骼；标签统一放在上方，悬停显示完整名称及「点击头部观察」。
- 同一人物的多个观察排队显示，一个头部同时只有一个可点击目标；收集后显示下一条，进入第二层、结束或重开时清空队列并恢复原材质覆盖层。收集仍使用原来的流程信号与右下角收集夹。
- 验证：Godot 4.6.1 Compatibility 实际渲染与 `tests/observation_actor_check.gd` 通过，覆盖全部绑定、头部坐标、弯腰跟随、真实鼠标拾取、同人物队列和材质恢复；`tools/Start-Godot.ps1 -Mode DialogueCheck` 通过，含课堂流程、暂停、重开及第二层。预览为 `.local/captures/observation-head.png`。
- 接入：已接入当前课堂场景，无需手动改主场景或项目配置；新增事件须填写 `observation_actor`。仍需人实际试玩，检查闪烁舒适度及不同视角下的操作感；未验证目标展示电脑及重新导出 Windows 包。

## 界面视觉改版（2026-11-07）

- 按用户确认的概念图采用墨绿、暖纸白、雾青配色。顶部控制条增加线性图标与分隔，放宽世界面片并轻微倾斜；保留既有按钮信号与射线输入映射。
- 世界字幕使用墨绿圆角底、说话人色细边和更宽留白，沿用头顶测量与底边间距，剧情原文不变。
- 第二层思绪改成暖纸白卡片、深绿正文、首句与后续句的字号层次，仍保留全部原文、世界锚点、引线、收集飞入与淡入淡出；新增标题文案放在内容配置 `ui.inner_os`。
- 收集夹改为单块墨绿底与细分隔行；最多八条的内容最小高度实测 302 px，落在原有 304 px 采样区内。菜单出现时暂收观察夹，菜单面片优先显示，避免思绪遮住继续与退出按钮。
- 接入已完成，无需改主场景、项目设置或课堂时序；已有未提交修改继续保留。
- 验证：Godot 4.6.1 Compatibility 下 DialogueCheck 通过；实际渲染截图覆盖开场、对话、回答、收集、L2 与 L3，另检查 960×540 暂停菜单及八条观察。截图与临时检查脚本在 `.local/`，不作为正式素材提交。
- 仍需人工完整试玩确认字号、阅读舒适度与情绪强度；未重新导出 Windows 安装包或验证展示电脑。
