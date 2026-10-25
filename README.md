# I See Me

心理课作业的 3D 镙头叙事 Demo：经历情境，观察自己，再观察正在观察的自己。

> 当前有可运行的三层镜头灰盒：内容提示、座位视角、回看自己、显露观察者和小样结束。
> 人物、教室与界面为几何体 / 临时占位；尚无正式剧情、分支、思绪倒放、声音或完整收束。
> 团队规则仍为可修改草案；骨架自测不代表完整游戏或真人体验验收已完成。
> 剧情已按[简化设计](docs/i%20see%20me%20简化设计.md)收敛为线性五环节、单一分支点，原三层多分支大纲仅作创意来源保留。

## 从哪里开始

| 文档 | 用途 |
| --- | --- |
| [简化设计](docs/i%20see%20me%20简化设计.md) | 当前剧情实施依据：五个环节、两个分支、思绪倒放与对观察的观察 |
| [开发计划](开发(unimportant).md) | Demo 内容、技术基线、七人分工、四周任务及验收 |
| [协作规则](CONTRIBUTING.md) | 分支、提交、PR、文件归属与任务转交 |
| [AI 工作约定](AGENTS.md) | 给 AI 的修改边界和验证要求 |
| [本机部署与启动](docs/setup.md) | D 盘便携版安装、启动和检查方式 |
| [第一周骨架与接入说明](docs/week1-runtime-skeleton.md) | 本地任务、模块接口、坐标约定、验收记录和剩余工作 |
| [L2 心流 / L3 抽离](docs/L2心流状态.md) | 灰黑无贴图 + 2 m 清晰球，以及只剩地板与主角的 L3 抽离、预览场景与主场景接线 |
| [教师动作与情绪动效](docs/教师动作与情绪动效-2026-10-23.md) | 教师 4 动作 × 5 情绪动效、完整调用方式、黑板对位与演示场景 |
| [角色动作补全（24 项）](docs/角色动作补全-24项-2026-10-24.md) | 主角/同学/教师/道具 24 项缺失动作：逐项说明、效果图、接入方式与演示场景 |
| [素材登记表](docs/素材登记.md) | 模型、声音、字体的来源与使用许可 |
| [原始大纲](大纲(unimportant).md) | 创意来源，已被简化设计取代，不作为实施依据 |

## 已确定的方向

- Godot 4.6.1 标准版、GDScript、Compatibility 渲染器。
- 只保证 Windows x64，简体中文，键鼠操作，离线运行。
- 一个教室事件、线性五个环节、单一分支点的两个分支，固定收束。
- 风格化低多边形；优先免费可用素材；AI 配音在制作阶段生成。
- 七人协作，你承担主开发与集成，其余六人先按实际参与制作分工。
- 四周安排，每人每周约 3–5 小时；主开发的实际投入另行确认。

## 获取项目

```powershell
git clone https://github.com/clcloudy/i-see-me.git
cd i-see-me
```

私有仓库的成员必须先获得访问权限，并使用自己的 GitHub 账号。
仓库所有者本机已部署在 `D:\tools\Godot\4.6.1`，可双击 `打开编辑器.cmd` 或 `查看房间.cmd`（现运行三层小样）。
其他成员需自行部署同版本引擎，详见[本机部署与启动](docs/setup.md)。

也可在项目目录启动与检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Play
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Capture
```

点击进入教室后依次查看三层，Esc 暂停。转场可跳过，重开返回内容提示并保留静音。
当前没有音源，静音只验证了总线状态；正式声音接入后仍需重新验证。

## 教师动效（2026-10-23）

教师第一版动效已完成：4 种课堂动作 × 5 种情绪可任意组合，全部为程序化骨骼动画，无需 AnimationPlayer。原静态教师 `scenes/actors/character_pose/teacher_stand.tscn` 保持不动，旧流程不受影响。

| 动作 | 枚举值 | 情绪 | 枚举值 |
| --- | --- | --- | --- |
| 讲课 `LECTURE` | 0 | 普通 `NEUTRAL` | 0 |
| 提问 `ASK` | 1 | 激昂 `EXCITED` | 1 |
| 点名 `CALL_ROLL` | 2 | 失落 `DOWN` | 2 |
| 板书 `WRITE_BOARD` | 3 | 疑惑 `PUZZLED` | 3 |
| | | 开心 `HAPPY` | 4 |

细节、逐项效果图和已知限制见[教师动作与情绪动效](docs/教师动作与情绪动效-2026-10-23.md)。

### 场景

| 场景 | 用途 | 操作 |
| --- | --- | --- |
| `scenes/actors/teacher/teacher_animated.tscn` | 单个动画教师，供正式流程实例化 | — |
| `scenes/actors/teacher/teacher_emotions_preview.tscn` | 5 种情绪并排对照 | `1/2/3` 切讲课/提问/点名，`A` 自动轮播 |
| `scenes/actors/teacher/teacher_writing_preview.tscn` | 5 种情绪同时板书 | — |
| `scenes/actors/teacher/teacher_classroom_preview.tscn` | 真教室集成演示（含 HUD） | `1-4` 动作，`QWERT` 情绪，`S` 说话，`空格` 暂停，`A` 自动轮播 |

在编辑器打开对应场景后按 **F6** 运行当前场景即可。演示场景的键盘操作由 `scripts/teacher_anim_demo.gd` / `teacher_emotion_lineup.gd` 提供，正式流程不需要这两个脚本。

### 调用方式

**实例化并设置状态：**

```gdscript
const TEACHER := preload("res://scenes/actors/teacher/teacher_animated.tscn")

var teacher := TEACHER.instantiate() as TeacherAnimator
teacher.position = Vector3(0.9, 0.15, -4.44)  # 真教室讲台平台
teacher.rotation_degrees.y = 180.0            # 面向 +Z 的学生
add_child(teacher)
teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.NEUTRAL)
```

**导出属性（编辑器可调）：**

| 属性 | 默认值 | 说明 |
| --- | --- | --- |
| `action` | `LECTURE` | 当前动作（运行时请用 `set_action`） |
| `emotion` | `NEUTRAL` | 当前情绪（运行时请用 `set_emotion`） |
| `playing` | `true` | 关闭后冻结在当前帧 |
| `time_scale` | `1.0` | 整体节奏倍率 |
| `phase_offset` | `0.0` | 相位偏移（秒），多个教师错开动作 |
| `show_props` | `true` | 显示粉笔 / 点名册 |
| `talking` | `true` | 说话口型开关（板书背对教室时自动闭嘴） |
| `speech_speed` | `1.0` | 口型语速倍率 |
| `turn_speed` | `3.5` | 转身插值速度 |
| `target_smoothing` | `12.0` | 手部目标点平滑速度 |

**运行时方法：**

| 方法 | 说明 |
| --- | --- |
| `set_action(action, immediate := false)` | 切换动作；`immediate=true` 立即转身/到位 |
| `set_emotion(emotion)` | 切换情绪（约 0.4 秒插值） |
| `set_state(action, emotion, immediate := false)` | 同时设置动作与情绪，流程最常用 |
| `cycle_action()` / `cycle_emotion()` | 循环到下一个动作 / 情绪 |
| `get_action_label()` / `get_emotion_label()` | 中文名，用于 HUD |
| `apply_pose()` | 立即重算一帧姿态 |
| `align_to_blackboard(board, distance := 0.47)` | 摆到黑板正面 0.47 m 并转向黑板（`y` 不变） |

**信号：**

```gdscript
teacher.action_changed.connect(func(a: int) -> void: print("动作 -> ", a))
teacher.emotion_changed.connect(func(e: int) -> void: print("情绪 -> ", e))
```

**板书对位：** 教师 root 到黑板正面的水平距离保持 **0.47 m**；黑板 +Z 面朝向教室，可直接 `teacher.align_to_blackboard($Classroom/Front/Board)`。真教室示例：黑板 `(0, 0, -4.94)`、板面厚 0.06 m，教师 root `(0.9, 0.15, -4.44)`。

**课堂流程示例：**

```gdscript
teacher.set_state(TeacherAnimator.Action.WRITE_BOARD, TeacherAnimator.Emotion.NEUTRAL)  # 写“坚持”
teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.NEUTRAL)      # 转回来讲话
teacher.set_state(TeacherAnimator.Action.ASK, TeacherAnimator.Emotion.PUZZLED)          # 提问
teacher.set_state(TeacherAnimator.Action.CALL_ROLL, TeacherAnimator.Emotion.NEUTRAL)    # 点名
teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.DOWN)         # 失落收束
```

每句台词前调用一次即可，动作会持续循环；只换情绪时用 `set_emotion()`，不会打断手部动作。板书转身约 1.2 秒，情绪过渡约 0.4 秒，硬切时才用 `immediate=true`。

### 面部口型与表情（2026-10-23）

Quaternius 模型脸上没有嘴、没有下颌骨、也没有 blend shape，所以 `scripts/teacher_face.gd` 在运行时**测量头部网格**（眼框、眉面片、下巴），在脸前补出三组贴面件并每帧跟随 Head 骨：

- **嘴**：深色口腔 + 牙齿，按音素序列开合（A/E/I/O/U/M/F/S/换气），幅度、嘴宽、嘴角随情绪变化；说话时嘴不会一直半张。
- **眉**：复制原模型的眉毛面片、略微放大外移，按情绪抬起/压低/内侧倾斜（疑惑单边挑眉）。
- **眼睑**：肤色面片从上眼睑落下，负责眨眼（2~5 秒一次）与眯眼（失落时更眯）。

动作只决定“说不说话”：讲课 / 提问 / 点名说话，板书（背对教室）闭嘴。`talking = false` 可整体关掉口型，用 `speech_speed` 调速。面部参数表在 `scripts/teacher_animator.gd` 的 `FACE_CONFIG`，与 `EMOTION_CONFIG`（身体）分开调。

### 粉笔与点名册握持（2026-10-23）

道具不再用固定偏移摆放，而是按**弯曲后的真实骨骼位置**计算：

- `_hand_frame()` 用 8 根指骨实时求手指方向、拇指方向与掌心法线（右手掌心法线 = 拇指 × 手指）。
- `_curl_fingers()` 按“掌心法线 × 手指方向”轴逐节弯曲四指与拇指；捏粉笔时食指中指只弯一半、无名指小指收紧（`HOLD_SCALES["pinch"]`）。
- 粉笔夹在食指中节掌侧凹槽里，笔身沿“手指 + 掌心”方向伸出 10 cm；点名册托在掌上，背面贴在实测的指背最高点（不会再被手指穿出封面）。

细节与效果图见[教师口型与握持](docs/教师口型与握持-2026-10-23.md)。

**自检：**

```powershell
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/teacher_anim_check.gd
```

## 角色动作补全（2026-10-24）

任务五缺失动作 **1~24 已全部完成**（主角 6 项、同学 10 项、教师 5 项、道具 3 项），
全部为运行时程序化动画/建模，无新增外部素材。逐项说明、效果图与接入代码见
[角色动作补全交付记录](docs/角色动作补全-24项-2026-10-24.md)。

| 预览场景 | 内容 | 操作 |
| --- | --- | --- |
| `scenes/actors/protagonist/protagonist_actions_preview.tscn` | 主角：起身/坐下、说话口型与手势、四处看、扶桌收回、输入站姿 | `1-7` 切换，`A` 自动，`R` 重播 |
| `scenes/actors/classmate/classmate_actions_preview.tscn` | 同学：低笑、点头、捡笔、回头、摇头、画方格、放低课本、交头接耳、忽然安静 | `1-9` 切换，`A` 自动，`R` 重播 |
| `scenes/actors/teacher/teacher_extra_preview.tscn` | **教师新增动作**：放下粉笔、放课本、指向你、走路、翻课本 | `1-5` 切换，`A` 自动，`R` 重播 |
| `scenes/actors/props/props_preview.tscn` | 道具 22~24：笔、课本/粉笔盒、铅笔/橡皮/本子 | 静态展示 |

在编辑器里用 **Ctrl+O** 打开上表的 `.tscn`，按 **F6** 运行当前场景即可；也可以直接：

```powershell
Godot_v4.6.1-stable_win64_console.exe --path . res://scenes/actors/teacher/teacher_extra_preview.tscn
```

可复用人物模板：`scenes/actors/protagonist/protagonist_animated.tscn`、
`scenes/actors/classmate/classmate_animated.tscn`；运行时用 `play_clip()` 切换动作。
正式课堂流程尚未接入（共享流程文件未改），接入方式见交付记录第八节。

## 开工前需要补齐
- 在开发计划中填写成员姓名、GitHub 用户名。
- 按协作规则完成每个人的第一次小样、提交与合并练习。
- 按接入说明提交独立成员小样，再由主开发集中集成。
- 本周后续安装匹配版本的导出模板并验证目标电脑；当前尚未配置 Windows 导出。

## 版权与隐私

仓库暂不设置覆盖全部代码和素材的开源许可证，公开或重新分发前由团队另行决定。
第三方素材按各自许可使用并登记；不上传账号凭据、同学个人经历、未经同意的肖像或声音。
