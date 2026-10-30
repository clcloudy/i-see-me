# 3D 场景内 UI（feat/3d-scene-ui）

把游戏界面从「铺在 2D 视图上的叠加层」改造为「放进三维场景里」，对应任务要求：

1. **全 3D，不平铺到视图上** —— 字幕、事件标记、声纹都存在于三维世界，随相机移动而具有空间位置与遮挡关系。
2. **可被观察到的事件 → 可点击收集的小球** —— 每条课堂事件在触发位置生成一颗发光小球（`EventOrb3D`），玩家用鼠标左键点击即可收集（收集后缩小上浮并消失）。
3. **说话字幕直接在说话者旁边出现** —— 说话时，3D 标签悬浮在对应说话者头部附近并始终朝向相机（`SceneUI3D` 复用 `DialogueFlow` 已有的说话者锚点）。
4. **发出动静的地方有声纹** —— 台词播放、教师走位、人物动作剪辑时，在该处生成向外扩散的环形声纹（`SoundRipple3D` + `shaders/ring_expand.gdshader`）。

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
- 声纹着色器兼容 GL Compatibility 渲染器；多级后处理不适用本项目。
- 点击收集依赖视口的三维拾取（默认开启）；若日后关闭需在项目设置里确认 `physics/3d/ray_picking`。
- 画面改动需由人在编辑器里实际试玩验收（自动测试不能替代完整流程与情绪强度判断）。

## 文件清单

- `scripts/scene_ui_3d.gd`（新增）3D UI 管理器
- `scripts/event_orb_3d.gd`（新增）可收集事件小球
- `scripts/sound_ripple_3d.gd`（新增）声纹
- `shaders/ring_expand.gdshader`（新增）声纹环形波纹着色器
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
