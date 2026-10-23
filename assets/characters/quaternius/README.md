# Quaternius Modular Men 角色模型

人物素材（D 人物负责，CHAR-001）。登记记录见 `docs/素材登记.md`。

## 来源与许可

- 作者 / 提供者：Quaternius（https://quaternius.com/packs/modularmen.html ）
- 许可：**CC0 1.0 Universal**（公有领域贡献），官网明确标示可个人、教育、商业免费使用，可修改、可随包分发，不要求署名。
- 完整许可文本：[LICENSE-CC0-1.0.txt](LICENSE-CC0-1.0.txt)。对外分发导出包时保留本目录即可。
- 下载来源：quaternius.com 官方包镜像 https://github.com/trebeljahr/quaternius-showcase （`public/glb/modular_men/` 与 `modular_women/`，与官方包同源）；下载日期 2026-10-17。
- 本项目当前实际使用 4 款（Casual、Casual2、WomensCasual、Suit）；其余 9 款为早期扩展造型，保留作其他场景备用，房间内已不再使用。如需追加新造型，先在素材登记表补登记再放入本目录。

## 文件

| 文件 | 用途 | 大小 |
| --- | --- | --- |
| Casual.glb | 主角 / 两个"自己"（坐姿、低头、抬头、反驳、写字、站姿全套姿态）；也作为男同学基础模型（卫衣+短裤） | 767 KB |
| Suit.glb | 教师（西装） | 838 KB |
| Casual2.glb | 男同学基础模型（短袖+长裤） | 742 KB |
| WomensCasual.glb | 女同学基础模型（短袖+长裤） | 786 KB |
| Worker.glb / Adventurer.glb / Beach.glb / Farmer.glb / Punk.glb | 男装备用造型（工装、户外、泳装、背带、朋克）。**非学生装扮，已不用于教室**，仅留作其他场景备用 | 658 KB–1.2 MB |
| WomensFormal.glb / WomensWorker.glb / WomensAdventurer.glb / WomensPunk.glb | 女装备用造型（正装、工装、户外、朋克）。**非学生装扮，已不用于教室**，仅留作其他场景备用 | 754 KB–1.2 MB |

> 2026-10-23 便装替换：教室里的同学只用 Casual / Casual2 / WomensCasual 三款学生便装，
> 通过 `character_pose.gd` 的 `outfit` 调色板（12 套配色）与 `height_scale`（身高 0.97–1.03）
> 区分个体，既保证全员学生装扮，又避免满座像克隆人。其余 9 款造型不再放进任何场景。

均为 glTF Binary，约 5,200–10,200 三角面，Humanoid 骨架，无内置动画、无表情 blendshape。
男女骨架手指骨命名略有差异（男 49 骨 / 女 51 骨），但躯干与四肢骨骼完全一致，
`scripts/character_pose.gd` 只用躯干四肢骨骼，全部模型通用。

## 在 Godot 中使用（接入必读）

1. **不要写骨骼位置**。该模型导入后 Skeleton3D 节点自带 100× 缩放 + 90° 旋转（Blender/glTF 导出惯例），骨骼局部坐标是厘米级；往骨骼位置字段写米制数值会被放大 100 倍，人物会沉入地板几十米。
2. **静态姿态 = 只旋转骨骼 + 移动角色根节点**。6 种姿态的骨骼角度表在 `scripts/character_pose.gd`；坐姿臀高 0.47 m 通过根节点下沉实现，场景内原点仍在地面。
3. 姿态场景在 `scenes/actors/character_pose/`，可直接实例化；模型朝向已统一为项目约定的局部 -Z。
   - 主角：`stand / sit / head_down / head_up / rebut / writing.tscn`；对话扩展 `stand_talk`（站起看向讲台说话）、`look_around`（躲避视线四处看）
   - 教师：`teacher_stand.tscn`
   - 同学（3 款便装基础模型，配色见下条）：`classmate_casual2_*`（男·短袖）、`classmate_casual_*`（男·卫衣）、`classmate_womenscasual_*`（女）；每种都有 `_sit`（坐姿）、`_down`（低头，对应思绪倒放环节"同学很快就低头了"）、`_whisper_l/r`（交头接耳）
   - 事件姿态（10.22 任务）：`event_cover_mouth.tscn`（E02 掩嘴低笑，两骨 IK 手到嘴边）、`event_side_glance.tscn`（E02 侧脸看向声源）、`event_nod.tscn`（E03 轻轻点头）
   - 满座教室：`classroom_seating.tscn`（42 座全满，主角在第二排第七位）
   - 对话时刻预览：`classroom_dialogue_preview.tscn`（真教室 + 教师 + 主角站讲 + E02/E03 + 议论同学）
   - 全员预览：`preview.tscn`（前排主角 6 姿态，后排教师+6 同学）
4. **同学配色**：实例上设 `outfit = 1..12`（`OUTFIT_PALETTES`，0 = 模型原色），按 上衣/裤子/鞋/头发 四组材质改色，肤色按系数微调；每件实例复制自己的材质，互不影响。`height_scale` 可做 0.97–1.03 的轻微身高差。改配色只动 `character_pose.gd` 里的常量，不用新建模型或场景。
5. 材质统一由 `scripts/character_pose.gd` 在运行时设为粗糙、无高光（Compatibility 渲染器兼容）；不修改 .glb 源文件。
6. 膝盖弯曲等角度已用批量渲染扫描校准（90° 会小腹突出、180° 过度折叠，110° 垂直自然），没有把握不要凭感觉改。
