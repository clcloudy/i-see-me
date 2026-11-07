# Windows Demo 打包

主游戏入口为 `scenes/classroom_dialogue.tscn`，项目版本 `0.1.0-demo`。
原有 `scenes/main.tscn` 是旧灰盒小样，保留供骨架检查；发行包不以它启动。
不调整根目录《流程控制(veryimportant).md》的时序。

## 本机准备

使用 `D:\tools\Godot\4.6.1` 的便携标准版及 `_sc_` 标记。
官方模板下载到非 C 盘：

https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz

完整 tpz 的 SHA-256（官方 GitHub Release 资产摘要）：

`e6d372afd4fdfaae9571eb5e3568afcd96ce6db9a569244034154faf0ac69875`

核对后解出 `templates/windows_release_x86_64.exe` 和 `templates/version.txt`，
放在 `D:\tools\Godot\4.6.1\editor_data\export_templates\4.6.1.stable\`。
只需 Windows x64 release 模板；构建不依赖 .NET、rcedit 或签名工具。

## 检查与构建

先运行课堂主流程检查，再打包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-Godot.ps1 -Mode DialogueCheck
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-Windows.ps1
```

重复构建时使用新的 `-BuildName`，例如 `I-See-Me-0.1.0-demo-windows-x64-r2`。
脚本拒绝覆盖已有目录或压缩包。输出均在被 Git 忽略的 `dist/` 中。
日志在 `.local/logs/<BuildName>/`；构建检查导入、导出及独立发行程序启动的退出码与 Godot 错误日志。

预设按主课堂场景及其依赖导出，显式补入脚本所引用的辅助类、着色器与图标，并包含通过 JSON 动态加载的 15 个现有音轨及
`content/classroom_dialogue.json`。新增音轨后应同步 `export_presets.cfg`。
构建使用编辑器生成 `assets/lightmaps/classroom_uv2_cache.res`，发行模板直接应用这份 UV2 数据，
不在运行时调用仅编辑器支持的 `lightmap_unwrap`。缓存是可重建的忽略文件，不改源场景或重烘光照。
不导出测试、演示场景、开发文档、原始素材包、本机日志、未知临时文件或凭据。
脚本不自动下载模板、不推送、不创建远程 Release。

## 包内容与交付

ZIP 包含整个文件夹：exe、pck、中文说明、第三方声明、许可全文、构建信息、逐文件摘要。
ZIP 旁另附 `.zip.sha256`。整体打包分发；不要仅发送 exe。
使用真正的 release 模板，关闭调试控制台包装器，未进行代码签名。

每次交付前，应将 ZIP 解压至独立目录并验证脱离工程运行，检查中文、声音、回答、
收集、第二层、暂停/继续、静音、跳过、重开和退出，以及错误日志。
完整画面、情绪强度、展示电脑离线运行和性能必须由人实际验收。
当前为部分内容与配音已接入的 Demo，不能称为完整正式游戏。
