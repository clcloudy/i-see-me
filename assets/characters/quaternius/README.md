# Quaternius Modular Men 角色模型

人物素材（D 人物负责，CHAR-001）。登记记录见 `docs/素材登记.md`。

## 来源与许可

- 作者 / 提供者：Quaternius（https://quaternius.com/packs/modularmen.html ）
- 许可：**CC0 1.0 Universal**（公有领域贡献），官网明确标示可个人、教育、商业免费使用，可修改、可随包分发，不要求署名。
- 完整许可文本：[LICENSE-CC0-1.0.txt](LICENSE-CC0-1.0.txt)。对外分发导出包时保留本目录即可。
- 下载来源：quaternius.com 官方包镜像 https://github.com/trebeljahr/quaternius-showcase （`public/glb/modular_men/`，与官方包同源）；下载日期 2026-10-17。
- 该包还有更多角色（Adventurer、King、Swat 等 11 款），本项目当前只用 3 款；如需追加，先在素材登记表补登记再放入本目录。

## 文件

| 文件 | 用途 | 大小 |
| --- | --- | --- |
| Casual.glb | 学生 / 两个"自己"（坐姿、低头、抬头、反驳、写字、站姿全套姿态） | 767 KB |
| Suit.glb | 教师（西装） | 838 KB |
| Worker.glb | 同学 / 配角（工装） | 658 KB |

均为 glTF Binary，约 5,200–6,600 三角面，49 骨 Humanoid 骨架，无内置动画、无表情 blendshape。

## 在 Godot 中使用（接入必读）

1. **不要写骨骼位置**。该模型导入后 Skeleton3D 节点自带 100× 缩放 + 90° 旋转（Blender/glTF 导出惯例），骨骼局部坐标是厘米级；往骨骼位置字段写米制数值会被放大 100 倍，人物会沉入地板几十米。
2. **静态姿态 = 只旋转骨骼 + 移动角色根节点**。6 种姿态的骨骼角度表在 `scripts/character_pose.gd`；坐姿臀高 0.47 m 通过根节点下沉实现，场景内原点仍在地面。
3. 姿态场景在 `scenes/actors/character_poses/`，可直接实例化；模型朝向已统一为项目约定的局部 -Z。
4. 材质统一由 `scripts/character_pose.gd` 在运行时设为粗糙、无高光（Compatibility 渲染器兼容）；不修改 .glb 源文件。
5. 膝盖弯曲等角度已用批量渲染扫描校准（90° 会小腹突出、180° 过度折叠，110° 垂直自然），没有把握不要凭感觉改。
