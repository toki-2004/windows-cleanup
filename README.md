# Windows Cleanup Helper

> **Language:** English | [简体中文 (Chinese)](README.zh-CN.md)

A safe, generalized PowerShell script that scans and cleans common Windows junk:
browser caches, temp files, crash dumps, thumbnail caches, package manager
caches, updater leftovers, old launcher versions, system caches, and more.

## One-click (Windows)

To run the tool without typing commands, double-click `一键清理.bat`
(keep it in the same folder as `windows-cleanup.ps1`):

* [1] Scan only - report what can be cleaned, deletes nothing
* [2] Quick clean - SAFE items (100% junk)
* [3] Deep clean - SAFE + ASK items (also regenerable caches)
* [4] Admin deep clean - also ADMIN items (UAC prompt)
* [0] Exit

## Safety first

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
  crash dumps, thumbnail caches, WebCache, old MATLAB ServiceHost versions.
* ASK: uv / npm / pip / Unity caches, game scratch caches, Tencent app caches
  (WeChat mini-program runtimes), WPS addons, updater leftover installers,
  old launcher versions, Recycle Bin.
* ADMIN: Windows Temp, Windows Update download cache, Visual Studio installer
  cache, system Package Cache, Logitech G HUB cache, Timi game update leftovers.

## Notes

* Works on Windows 10/11 with Windows PowerShell 5.1 or PowerShell 7+.
* Uses only environment variables and contains no hardcoded usernames, so it
  adapts to any user profile.
* Deleted items are NOT sent to the Recycle Bin (except the Recycle Bin itself).
* Locked files (app currently running) are skipped and reported; close the app
  and run the script again.
* For conda package caches, prefer `conda clean --all` instead of deleting
  folders directly.
* Deleting the system Package Cache / VS installer cache means some programs
  will re-download installers for repair or uninstall.

## License

This project is licensed under the [MIT License](LICENSE).
