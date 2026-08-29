# Windows 清理助手

> **语言：** English ([English README](README.md)) | 简体中文

一个安全、通用的 PowerShell 脚本：扫描并清理 Windows 常见垃圾与缓存，包括
浏览器/Steam 缓存、临时文件、崩溃转储、缩略图缓存、微信/QQ/剪映日志、
GPU 着色器缓存、包管理器缓存（含 conda）、更新器残留、旧版启动器版本、
系统日志与转储等。

![扫描报告](assets/scan-report.png)

若不便于手动输入命令，可直接双击 `一键清理.bat`（将其与 windows-cleanup.ps1 置于同一目录）：

* [1] 只扫描 - 查看可清理内容，不删除任何文件
* [2] 快速清理 - 删除 100% 垃圾（SAFE 项）
* [3] 深度清理 - 额外删除可再生的缓存（SAFE + ASK 项）
* [4] 管理员深度清理 - 包含系统级项目（会弹出 UAC 确认）
* [0] 退出

![一键菜单](assets/menu.png)
![清理前后磁盘空间对比](assets/disk-before-after.png)

所有可清理项目分为三类：

| 类别 | 含义 | 删除方式 |
| --- | --- | --- |
| SAFE | 100% 无用、可自动再生的内容 | `-Clean` |
| ASK | 可再生的但可能有用的内容 | `-Clean -Yes` |
| ADMIN | 系统级，需要管理员权限 | 管理员环境下 `-Clean -Yes` |

默认仅执行扫描，不删除任何文件。**在添加 `-Clean` 参数之前，不会删除任何内容。**

## 使用方法

```powershell
# 仅报告可清理内容（不做任何修改）
powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Scan

# 删除 SAFE 项（浏览器缓存、临时文件、崩溃转储、缩略图等）
powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Clean

# 同时删除 ASK 项（包缓存、更新器残留、回收站等）
powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Clean -Yes
```

系统级（ADMIN）项目需要在管理员 PowerShell 中运行：
右键点击"Windows PowerShell"或"终端"图标 → 选择"以管理员身份运行"，
然后再执行上面的命令。

## 清理内容

* SAFE：用户临时文件、浏览器缓存（Edge / Chrome / Brave / Firefox）、
  Steam 内置浏览器缓存、崩溃转储、缩略图缓存、WebCache、MATLAB ServiceHost
  旧版本、微信/QQ 日志与崩溃信息、剪映运行时缓存、NVIDIA / DirectX 着色器
  缓存、用户级错误报告（WER）。
* ASK：uv / npm / pip / Unity / cargo 缓存、conda 包缓存（自动调用
  `conda clean --all`）、游戏 scratch 缓存、微信内置浏览器缓存与小程序
  插件包（检测到微信进程运行时自动跳过）、WPS 插件组件、浏览器
  Service Worker 数据、更新器残留安装包（含抖音 app_shell_cache）、
  旧版启动器版本、回收站。
* ADMIN：Windows 临时文件、Windows 更新下载缓存、CBS 日志、系统错误报告
  （WER）、Visual Studio 安装包缓存、系统 Package Cache、Logitech G HUB
  缓存、天美游戏更新包残留。内核/内存转储（Minidump / MEMORY.DMP 等）刻意
  不清理：它们是蓝屏/卡死后唯一的现场证据。

## 安全设计

* 浏览器与 Steam 缓存按固定目录名精确匹配（Cache、Code Cache、GPUCache 等），
  不触碰书签、密码、Cookie、历史记录与本地存储。
* 聊天数据零接触：微信/QQ 只清理 log、crashinfo 与缓存目录，
  FileStorage、xwechat_files 等聊天记录目录不在清理范围。
* 微信内嵌浏览器运行时只清 HTTP 缓存与小程序插件包；radium 的 users、
  web、mmkv、locales 等引擎与会话数据一律不碰，且微信运行时（含
  WeChatAppEx 进程）会自动跳过相关项，避免表情搜索/内置浏览器/小程序
  渲染空白、需重启微信才恢复。
* 临时目录与系统日志（Temp、CBS、WER、Minidump 等）只清空内容、保留目录本身。
* conda 包缓存通过 `conda clean --all` 清理，找不到 conda 时自动跳过，
  不直接删除目录。
* 被程序占用的文件自动跳过并给出提示；关闭相应程序后重新运行即可。

## 说明

* 支持 Windows 10 / 11，兼容 Windows PowerShell 5.1 和 PowerShell 7+。
* 仅使用环境变量，未对用户名进行硬编码，可适配任意用户环境。
* 删除的文件不会进入回收站（回收站本身的清空除外）。
* 删除 GPU 着色器缓存（NVIDIA DXCache/GLCache、D3DSCache）后，首次启动游戏
  需要重新编译着色器，加载稍慢属正常现象。
* 删除系统 Package Cache / VS 安装包缓存后，部分程序在修复或卸载时需要
  重新下载安装器。

## 许可证

本项目基于 [MIT 许可证](LICENSE) 发布。
