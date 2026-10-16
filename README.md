# I See Me

心理课作业的 3D 镙头叙事 Demo：经历情境，观察自己，再观察正在观察的自己。

> 当前有可运行的三层镜头灰盒：内容提示、座位视角、回看自己、显露观察者和小样结束。
> 人物、教室与界面为几何体 / 临时占位；尚无正式剧情、行为选择、观察任务、声音或完整结尾。
> 团队规则仍为可修改草案；骨架自测不代表完整游戏或真人体验验收已完成。

## 从哪里开始

| 文档 | 用途 |
| --- | --- |
| [开发计划](开发(unimportant).md) | Demo 内容、技术基线、七人分工、四周任务及验收 |
| [协作规则](CONTRIBUTING.md) | 分支、提交、PR、文件归属与任务转交 |
| [AI 工作约定](AGENTS.md) | 给 AI 的修改边界和验证要求 |
| [本机部署与启动](docs/setup.md) | D 盘便携版安装、启动和检查方式 |
| [第一周骨架与接入说明](docs/week1-runtime-skeleton.md) | 本地任务、模块接口、坐标约定、验收记录和剩余工作 |
| [素材登记表](docs/素材登记.md) | 模型、声音、字体的来源与使用许可 |
| [原始大纲](大纲(unimportant).md) | 保留的创意来源，不自动覆盖 |

## 已确定的方向

- Godot 4.6.1 标准版、GDScript、Compatibility 渲染器。
- 只保证 Windows x64，简体中文，键鼠操作，离线运行。
- 一个教室事件、三层观察、三个行为、两个主动选择的收尾。
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

## 开工前需要补齐
- 在开发计划中填写成员姓名、GitHub 用户名。
- 按协作规则完成每个人的第一次小样、提交与合并练习。
- 按接入说明提交独立成员小样，再由主开发集中集成。
- 本周后续安装匹配版本的导出模板并验证目标电脑；当前尚未配置 Windows 导出。

## 版权与隐私

仓库暂不设置覆盖全部代码和素材的开源许可证，公开或重新分发前由团队另行决定。
第三方素材按各自许可使用并登记；不上传账号凭据、同学个人经历、未经同意的肖像或声音。
