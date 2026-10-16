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

# 直接查看房间。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Play

# 导入和结构检查，不弹出游戏窗口。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Check

# 实际渲染检查，自动保存两种窗口尺寸的截图并退出。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode Capture
```

也可双击项目根目录的 `打开编辑器.cmd` 或 `查看房间.cmd`。
其他成员可修改启动脚本参数 `-InstallDirectory` 为自己的非 C 盘目录，不需要修改项目场景。
启动器不会下载任何内容，也不会提交或推送代码。

## 当前工程内容

- `scenes/main.tscn`：场景入口、固定相机、环境和灯光。
- `scenes/room.tscn`：8 × 6 米的空房间，高 3.4 米，地板、天花板、四面墙及踢脚线。
- 房间由可在 Godot 编辑器直接选择和修改的基础网格组成，没有人物、家具、剧情和运行时脚本。
- 相机固定，无行走控制；可在编辑器 3D 视图里自由查看和调整。

这只是供后续开发使用的基础工程，不是四周计划里的完整 Demo。
