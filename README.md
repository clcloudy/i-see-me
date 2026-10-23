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
| [L2 心流状态](docs/L2心流状态.md) | 灰黑无贴图 + 2 m 清晰球的状态接口、预览场景与主场景接线 |
| [教师动作与情绪动效](docs/教师动作与情绪动效-2026-10-23.md) | 教师 4 动作 × 5 情绪动效、完整调用方式、黑板对位与演示场景 |
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
| `scenes/actors/teacher/teacher_classroom_preview.tscn` | 真教室集成演示（含 HUD） | `1-4` 动作，`QWERT` 情绪，`空格` 暂停，`A` 自动轮播 |

在编辑器打开对应场景后按 **F6** 运行当前场景即可。演示场景的键盘操作由 `scripts/teacher_anim_demo.gd` / `teacher_emotion_lineup.gd` 提供，正式流程不需要这两个脚本。

### 调用方式

**实例化并设置状态：**

```gdscript
const TEACHER := preload("res://scenes/actors/teacher/teacher_animated.tscn")

var teacher: TeacherAnimator = TEACHER.instantiate()
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

**自检：**

```powershell
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/teacher_anim_check.gd
```

## 开工前需要补齐
- 在开发计划中填写成员姓名、GitHub 用户名。
- 按协作规则完成每个人的第一次小样、提交与合并练习。
- 按接入说明提交独立成员小样，再由主开发集中集成。
- 本周后续安装匹配版本的导出模板并验证目标电脑；当前尚未配置 Windows 导出。

## 版权与隐私

仓库暂不设置覆盖全部代码和素材的开源许可证，公开或重新分发前由团队另行决定。
第三方素材按各自许可使用并登记；不上传账号凭据、同学个人经历、未经同意的肖像或声音。
