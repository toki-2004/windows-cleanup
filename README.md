# Windows Cleanup Helper

> **Language:** English | [简体中文 (Chinese)](README.zh-CN.md)

A safe, generalized PowerShell script that scans and cleans common Windows junk:
browser/Steam caches, temp files, crash dumps, thumbnail caches, WeChat/QQ/CapCut
logs, GPU shader caches, package manager caches (including conda), updater
leftovers, old launcher versions, system logs and memory dumps.

![Scan report](assets/scan-report.png)

To run the tool without typing commands, double-click `一键清理.bat`
(keep it in the same folder as `windows-cleanup.ps1`):

* [1] Scan only - report what can be cleaned, deletes nothing
* [2] Quick clean - SAFE items (100% junk)
* [3] Deep clean - SAFE + ASK items (also regenerable caches)
* [4] Admin deep clean - also ADMIN items (UAC prompt)
* [0] Exit

![Menu](assets/menu.png)
![Disk before/after](assets/disk-before-after.png)

Everything is split into three categories:

| Category | Meaning | Removed with |
| --- | --- | --- |
| SAFE | 100% junk, regenerated automatically | `-Clean` |
| ASK | Regenerable but possibly useful | `-Clean -Yes` |
| ADMIN | System-level, needs an elevated shell | `-Clean -Yes` in an admin shell |

The default is scan-only. **Nothing is deleted until you pass `-Clean`.**

## Usage

```powershell
# Report what can be cleaned (no changes)
powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Scan

# Delete SAFE items (browser caches, temp, crash dumps, thumbnails, ...)
powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Clean

# Also delete ASK items (package caches, updater leftovers, recycle bin, ...)
powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Clean -Yes
```

For ADMIN items, run the script from an elevated PowerShell
(right-click the PowerShell icon > Run as administrator).

## What is cleaned

* SAFE: user temp files, browser caches (Edge / Chrome / Brave / Firefox),
  Steam's embedded browser cache, crash dumps, thumbnail caches, WebCache, old
  MATLAB ServiceHost versions, WeChat/QQ logs and crash info, CapCut runtime
  caches, NVIDIA / DirectX shader caches, user-level Windows Error Reporting.
* ASK: uv / npm / pip / Unity / cargo caches, conda package cache (runs
  `conda clean --all` automatically), game scratch caches, Tencent app caches
  (WeChat mini-program runtimes), WPS addons, browser Service Worker data,
  updater leftover installers (including Douyin app_shell_cache), old launcher
  versions, Recycle Bin.
* ADMIN: Windows Temp, Windows Update download cache, CBS logs, system error
  reports (WER), Visual Studio installer cache, system Package Cache,
  Logitech G HUB cache, Timi game update leftovers. Kernel/memory dumps
  (Minidump / MEMORY.DMP) are deliberately NOT cleaned: they are the only
  forensic evidence after a bluescreen or freeze.

## Safety mechanisms

* Browser and Steam caches are matched by exact folder names (Cache,
  Code Cache, GPUCache, ...); bookmarks, passwords, cookies, browsing history
  and local storage are never touched.
* Chat data is off limits: WeChat/QQ only expose their log, crash info and
  cache folders; chat history folders (FileStorage, xwechat_files, ...) are
  not in scope.
* Temp folders and system logs (Temp, CBS, WER, Minidump, ...) are emptied in
  place - the folders themselves are kept.
* The conda package cache is cleaned via `conda clean --all`; if conda cannot
  be found, the item is skipped and the folder is never deleted directly.
* Locked files (app currently running) are skipped and reported; close the app
  and run the script again.

## Notes

* Works on Windows 10/11 with Windows PowerShell 5.1 or PowerShell 7+.
* Uses only environment variables and contains no hardcoded usernames, so it
  adapts to any user profile.
* Deleted items are NOT sent to the Recycle Bin (except the Recycle Bin itself).
* After GPU shader caches (NVIDIA DXCache/GLCache, D3DSCache) are deleted, the
  first game launch recompiles shaders and starts slightly slower.
* Deleting the system Package Cache / VS installer cache means some programs
  will re-download installers for repair or uninstall.

## License

This project is licensed under the [MIT License](LICENSE).
