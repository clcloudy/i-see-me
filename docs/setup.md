# Godot 本机部署与启动

## 安装位置

- 引擎：`D:\tools\Godot\4.6.1`
- 原始压缩包：`D:\tools\Godot\downloads\Godot_v4.6.1-stable_win64.exe.zip`
- 便携编辑器数据：`D:\tools\Godot\4.6.1\editor_data`
- 启动器的临时目录和应用数据：`D:\tools\Godot\4.6.1\runtime`
- 项目缓存：项目内 `.godot/`，日志与验证截图：项目内 `.local/`；均不提交。

使用官方 Godot 4.6.1 Windows x64 标准版，不需要安装 .NET，也不修改全局 PATH。
安装目录含 `_sc_` 标记，启用自包含模式。启动脚本还为子进程指定 D 盘的 APPDATA、LOCALAPPDATA、TEMP 和 TMP。
这些设置只影响本次启动，不修改系统环境变量；不承诺控制 Windows 自身或显卡驱动的系统级写入位置。

下载来源：[官方版本页面](https://godotengine.org/download/archive/4.6.1-stable/)。
压缩包 SHA-256（已与官方发布资产摘要核对）：

```text
088da0457e2d1f7f8a45e6d4605a42b756ea33b9ccd75059bdbc01bb31c2b40d
```

当前只需编辑和运行项目，未下载体积较大的导出模板。
以后需要导出 Windows 程序时，再下载匹配的 4.6.1 模板到 D 盘的便携数据目录；不要直接使用默认用户目录安装。

## 启动

在项目目录执行：

```powershell
# 打开编辑器，F6 运行当前场景，F5 运行整个项目。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1

# 直接运行三层灰盒小样。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Play

# 导入、流程交互与各阶段退出检查，不弹出游戏窗口。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Check

# 实际渲染检查，自动保存两种窗口尺寸下的各层与界面截图并退出。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Capture
```

也可双击项目根目录的 `打开编辑器.cmd` 或 `查看房间.cmd`（现运行三层小样）。
其他成员可修改启动脚本参数 `-InstallDirectory` 为自己的非 C 盘目录，不需要修改项目场景。
启动器不会下载任何内容，也不会提交或推送代码。

## 当前工程内容

- `scenes/main.tscn`：场景入口，组合灰盒教室、镜头、界面和唯一流程控制器，保留环境和灯光。
- `scenes/room.tscn`：8 × 6 米的空房间，高 3.4 米，地板、天花板、四面墙及踢脚线。
- `scenes/classroom.tscn`、`scenes/actors/`、`scenes/props/`：可替换的几何体教室、人物与课桌占位。
- `scenes/camera_rig.tscn`：三个预设位置和注视目标，无行走控制。
- `scenes/ui/prototype_ui.tscn`：临时界面；`scripts/`：流程、镜头、空间显露与界面脚本。
- `content/prototype.json`：所有小样文案，正式剧情与声音尚未接入。

小样依次显示内容提示、L1、L2、L3 与结束页；Esc 暂停，转场期间可跳过。
它是供成员接入的运行骨架，不是四周计划里的完整 Demo。接口与验收记录见[第一周说明](week1-runtime-skeleton.md)。

`Check` 会检查导入、流程、防重复点击、暂停恢复、静音重开及七种退出路径。
`Capture` 会在 1280×720 与 960×540 下检查并保存三层、转场、提示、暂停和结束画面。
日志位于 `.local/logs/`（`import.log`、`check.log`、`capture.log`、`quit-*.log`），截图位于 `.local/captures/`，均不提交。
启动检查同时核对退出码与错误日志。画面及三层理解度仍须人实际检查。
