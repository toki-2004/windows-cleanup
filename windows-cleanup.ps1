<#
.SYNOPSIS
  Windows disk cleanup - scan and remove common junk/cache files safely.

.DESCRIPTION
  Categories:
    SAFE  - 100% junk, regenerated automatically
            (temp files, browser/Steam caches, app logs, shader caches,
             crash dumps, thumbnails)
    ASK   - regenerable but possibly useful
            (package caches - conda via "conda clean", updater leftovers,
             old app versions, Service Worker data, recycle bin)
    ADMIN - system-level, requires an elevated shell
            (Windows Temp, Windows Update cache, ProgramData caches,
             CBS/WER logs; memory dumps are kept as crash evidence)

  Default mode is -Scan: nothing is deleted, only sizes are reported.
  Use -Clean to delete SAFE items. Add -Yes to also delete ASK items.
  ADMIN items are attempted only when running as Administrator.

.PARAMETER Scan
  Only report sizes and recommendations (default).

.PARAMETER Clean
  Delete SAFE items (and ASK items if -Yes is given).

.PARAMETER Yes
  Also delete ASK items. Use together with -Clean.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Scan
  powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Clean
  powershell -ExecutionPolicy Bypass -File windows-cleanup.ps1 -Clean -Yes
#>

param(
  [switch]$Scan,
  [switch]$Clean,
  [switch]$Yes
)

$ErrorActionPreference = "SilentlyContinue"

function Get-SizeMB([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return 0 }
  $sum = (Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  return [math]::Round($sum / 1MB, 1)
}

function Get-ItemSizeMB($item) {
  return [math]::Round($item.Length / 1MB, 1)
}

$script:items = @()

function Add-Item([string]$path, [string]$label, [string]$cat, [switch]$ClearContents, [string]$Action) {
  if (-not $path) { return }
  if (-not (Test-Path -LiteralPath $path)) { return }
  $size = Get-SizeMB $path
  if ($size -gt 0) {
    $script:items += [PSCustomObject]@{ Path = $path; Label = $label; Cat = $cat; SizeMB = $size; ClearContents = [bool]$ClearContents; Action = $Action }
  }
}

function Add-File($item, [string]$label, [string]$cat) {
  if (-not $item) { return }
  $size = Get-ItemSizeMB $item
  if ($size -gt 0) {
    $script:items += [PSCustomObject]@{ Path = $item.FullName; Label = $label; Cat = $cat; SizeMB = $size; ClearContents = $false }
  }
}

function Scan-CacheDirs([string]$root, [string]$labelPrefix, [string[]]$names, [string]$cat) {
  if (-not $root -or -not (Test-Path -LiteralPath $root)) { return }
  Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $names -ccontains $_.Name } |
    ForEach-Object {
      $rel = $_.FullName.Substring($root.Length).TrimStart('\')
      Add-Item $_.FullName ($labelPrefix + $rel) $cat
    }
}

# Numeric version key for "keep the newest" comparisons: plain string sort
# would rank v1.9 above v1.10 and delete the in-use newer version.
function Get-VersionKey([string]$name) {
  $m = [regex]::Match($name, '\d+(\.\d+)*')
  if (-not $m.Success) { return [long]-1 }
  $parts = @($m.Value.Split('.') | ForEach-Object { [int]$_ })
  while ($parts.Count -lt 4) { $parts += 0 }
  return [long](("{0:D5}{1:D5}{2:D5}{3:D5}" -f $parts[0], $parts[1], $parts[2], $parts[3]))
}

$L = $env:LOCALAPPDATA
$R = $env:APPDATA

# ---------- SAFE items ----------
Add-Item (Join-Path $L "Temp") "User temp files (contents)" "SAFE" -ClearContents
Add-Item (Join-Path $L "CrashDumps") "Crash dumps" "SAFE"
Add-Item (Join-Path $L "Microsoft\Windows\WebCache") "WebCache (close browsers first)" "SAFE"

# Browser caches: exact folder names only, never profile/cookie data.
# Service Worker / Media Cache go to ASK (some web apps keep offline state there).
$cacheNames = @("Cache", "Code Cache", "GPUCache", "GrShaderCache", "ShaderCache", "DawnWebGPUCache", "cache2")
$swNames = @("Service Worker", "Media Cache")
$chromiumRoots = @(
  (Join-Path $L "Microsoft\Edge\User Data"),
  (Join-Path $L "Google\Chrome\User Data"),
  (Join-Path $L "BraveSoftware\Brave-Browser\User Data")
)
foreach ($root in $chromiumRoots) { Scan-CacheDirs $root "Browser cache: " $cacheNames "SAFE" }
foreach ($root in $chromiumRoots) { Scan-CacheDirs $root "Browser Service Worker: " $swNames "ASK" }
Scan-CacheDirs (Join-Path $R "Mozilla\Firefox\Profiles") "Browser cache: " $cacheNames "SAFE"
# Steam embedded browser: cache-like subfolders only, keeps cookies/localStorage
Scan-CacheDirs (Join-Path $L "Steam\htmlcache") "Steam web cache: " $cacheNames "SAFE"

# App logs / crash info (regenerate on next run; chat data folders untouched)
Add-Item (Join-Path $R "Tencent\xwechat\log") "WeChat(New) log" "SAFE"
Add-Item (Join-Path $R "Tencent\xwechat\crashinfo") "WeChat(New) crash info" "SAFE"
Add-Item (Join-Path $R "Tencent\WeChat\log") "WeChat classic log" "SAFE"
Add-Item (Join-Path $R "Tencent\QQ\webkitex_cache") "QQ embedded browser cache" "SAFE"

# CapCut runtime caches only; Projects/Resources hold user data. Download cache is ASK (below).
# CEF is scanned for cache-like subfolders only (it also holds cookies/local storage).
$capcut = Join-Path $L "JianyingPro\User Data"
Scan-CacheDirs (Join-Path $capcut "CEF") "CapCut CEF cache: " $cacheNames "SAFE"
Add-Item (Join-Path $capcut "Log") "CapCut log" "SAFE"
Add-Item (Join-Path $capcut "Tracking") "CapCut tracking logs" "SAFE"

# GPU shader caches (regenerated; first game/app launch recompiles shaders)
Add-Item (Join-Path $L "NVIDIA\DXCache") "NVIDIA DX shader cache" "SAFE"
Add-Item (Join-Path $L "NVIDIA\GLCache") "NVIDIA GL shader cache" "SAFE"
Add-Item (Join-Path $L "NVIDIA\OptixCache") "NVIDIA Optix cache" "SAFE"
Add-Item (Join-Path $L "D3DSCache") "DirectX shader cache" "SAFE"

# Windows Error Reporting, user level: queued crash reports only
Add-Item (Join-Path $L "Microsoft\Windows\WER") "WER reports user (contents)" "SAFE" -ClearContents

# Explorer thumbnail cache
$thumbDir = Join-Path $L "Microsoft\Windows\Explorer"
if (Test-Path -LiteralPath $thumbDir) {
  Get-ChildItem -LiteralPath $thumbDir -Filter "thumbcache_*.db" -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { Add-File $_ ("Thumbnail cache: " + $_.Name) "SAFE" }
}

# MATLAB ServiceHost: old versions + logs (keep the newest by numeric version)
$msh = Join-Path $L "MathWorks\ServiceHost"
if (Test-Path -LiteralPath $msh) {
  $versions = Get-ChildItem -LiteralPath $msh -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^v[\d.]+$' } |
    Sort-Object { Get-VersionKey $_.Name } -Descending
  if ($versions.Count -gt 1) {
    $keep = $versions[0].Name
    $versions | Select-Object -Skip 1 |
      ForEach-Object { Add-Item $_.FullName ("MATLAB ServiceHost old: " + $_.Name + " (keep " + $keep + ")") "SAFE" }
  }
  Add-Item (Join-Path $msh "logs") "MATLAB ServiceHost logs" "SAFE"
}

# ---------- ASK items ----------
Add-Item (Join-Path $L "uv\cache") "uv package cache" "ASK"
Add-Item (Join-Path $L "npm-cache") "npm cache" "ASK"
Add-Item (Join-Path $L "pip\cache") "pip cache" "ASK"
Add-Item (Join-Path $L "Unity\cache") "Unity cache" "ASK"
Add-Item (Join-Path $L "ForzaHorizon4\scratch") "Forza Horizon 4 scratch cache" "ASK"

# Tencent app caches (mini-program / built-in browser runtimes)
Add-Item (Join-Path $R "Tencent\xwechat\radium") "WeChat(New) radium cache" "ASK"
Add-Item (Join-Path $R "Tencent\xwechat\xplugin") "WeChat(New) xplugin cache" "ASK"
Add-Item (Join-Path $R "Tencent\WeChat\XPlugin") "WeChat XPlugin cache" "ASK"
Add-Item (Join-Path $R "Kingsoft\wps\addons") "WPS addons/components" "ASK"

# conda: cleaned via "conda clean --all" in clean mode, never deleted directly
Add-Item (Join-Path $env:USERPROFILE "miniconda3\pkgs") "conda package cache (conda clean)" "ASK" -Action "CondaClean"
Add-Item (Join-Path $env:USERPROFILE ".cargo\registry") "cargo registry cache" "ASK"
Add-Item (Join-Path $capcut "Download") "CapCut downloaded materials cache" "ASK"

# Recycle bin (permanent delete - only with -Yes)
$rbPath = "C:\`$Recycle.Bin"
$rbSize = Get-SizeMB $rbPath
if ($rbSize -gt 0) {
  $script:items += [PSCustomObject]@{ Path = $rbPath; Label = "Recycle Bin (permanent)"; Cat = "ASK"; SizeMB = $rbSize; ClearContents = $false; Action = "RecycleBin" }
}

# Updater leftover installers: installer.exe inside *updater* folders
Get-ChildItem -LiteralPath $L -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "updater" } |
  ForEach-Object {
    Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match "^installer.*\.exe$" } |
      ForEach-Object { Add-File $_ ("Updater leftover: " + $_.Directory.Name + "\" + $_.Name) "ASK" }
  }

# Douyin desktop installer cache: app_shell_cache_<id> folders in LocalAppData
Get-ChildItem -LiteralPath $L -Directory -Filter "app_shell_cache_*" -Force -ErrorAction SilentlyContinue |
  ForEach-Object { Add-Item $_.FullName "Douyin installer cache" "ASK" }

# Old app-* versions in launchers (group within the same parent folder only,
# keep the newest by numeric version - see Get-VersionKey)
Get-ChildItem -LiteralPath $L -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "^(app|pcr)-\d" } |
  Group-Object { $_.Parent.FullName + "::" + ($_.Name -replace "-\d[\d.]*$", "") } |
  ForEach-Object {
    $group = @($_.Group | Sort-Object { Get-VersionKey $_.Name } -Descending)
    if ($group.Count -gt 1) {
      $keep = $group[0].Name
      $group | Select-Object -Skip 1 |
        ForEach-Object { Add-Item $_.FullName ("Old launcher version: " + $_.Name + " (keep " + $keep + ")") "ASK" }
    }
  }

# ---------- ADMIN items ----------
Add-Item (Join-Path $env:ProgramData "Timi Personal Computing\Update") "Timi game update leftovers" "ADMIN"
Add-Item (Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages") "Visual Studio installer cache" "ADMIN"
Add-Item (Join-Path $env:ProgramData "Package Cache") "System Package Cache" "ADMIN"
Add-Item (Join-Path $env:ProgramData "LGHUB\cache") "Logitech G HUB cache" "ADMIN"
Add-Item "C:\Windows\Temp" "Windows Temp (contents)" "ADMIN" -ClearContents
Add-Item "C:\Windows\SoftwareDistribution\Download" "Windows Update download cache" "ADMIN"
Add-Item "C:\Windows\Logs\CBS" "CBS logs (contents)" "ADMIN" -ClearContents
Add-Item (Join-Path $env:ProgramData "Microsoft\Windows\WER") "WER reports system (contents)" "ADMIN" -ClearContents
# Memory dumps (Minidump / LiveKernelReports / MEMORY.DMP) are intentionally NOT
# in this list: they are the only forensic evidence after a bluescreen/freeze,
# and this machine is in a freeze-investigation period. Clean them manually
# only after the evidence is no longer needed.

# ---------- report ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Output "=========================================="
Write-Output " Windows Cleanup"
Write-Output (" Machine: " + $env:COMPUTERNAME + "   Elevated: " + $isAdmin)
Write-Output (" Free C:  " + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + " GB")
Write-Output "=========================================="

if ($script:items.Count -eq 0) {
  Write-Output "No junk found. Nothing to do."
} else {
  $script:items | Sort-Object Cat, SizeMB -Descending |
    Format-Table @{n = "Cat"; e = { $_.Cat } }, @{n = "SizeMB"; e = { $_.SizeMB } }, Label, Path -AutoSize |
    Out-String -Width 240 | Write-Output

  foreach ($g in ($script:items | Group-Object Cat)) {
    $total = ($g.Group | Measure-Object SizeMB -Sum).Sum
    Write-Output ("Total " + $g.Name + ": " + [math]::Round($total / 1024, 2) + " GB")
  }
}

function Remove-JunkItem($it) {
  $before = Get-SizeMB $it.Path
  if ($it.ClearContents) {
    # Windows PowerShell 5.1 Remove-Item -Recurse FOLLOWS directory junctions
    # and would recurse into their targets. Snapshot first, then per child:
    # reparse points are deleted as links only, dirs via rmdir (which also
    # never enters junction targets), plain files directly.
    $children = @(Get-ChildItem -LiteralPath $it.Path -Force -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
      if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue
      } elseif ($child.PSIsContainer) {
        cmd /c rmdir /s /q "$($child.FullName)" 2>&1 | Out-Null
      } else {
        Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue
      }
    }
  } else {
    # rmdir /s /q removes the directory itself without entering junction
    # targets (PS 5.1 Remove-Item -Recurse would follow them and could wipe
    # user data behind a junction).
    cmd /c rmdir /s /q "$($it.Path)" 2>&1 | Out-Null
  }
  $after = Get-SizeMB $it.Path
  return ($before - $after)
}

if ($Clean) {
  Write-Output ""
  Write-Output "=== CLEAN MODE ==="
  $freed = 0
  $targets = @($script:items | Where-Object { $_.Cat -eq "SAFE" })
  if ($Yes) {
    $targets += @($script:items | Where-Object { $_.Cat -eq "ASK" })
  }
  foreach ($it in $targets) {
    if ($it.Action -eq "RecycleBin") {
      if ($Yes) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $after = Get-SizeMB $it.Path
        $f = $it.SizeMB - $after
        if ($f -gt 0) { Write-Output ("Deleted " + $it.Label + " (-" + $f + " MB)") }
        else { Write-Output ("Skipped/locked " + $it.Label) }
        $freed += $f
      }
      continue
    }
    if ($it.Action -eq "CondaClean") {
      $conda = Join-Path $env:USERPROFILE "miniconda3\Scripts\conda.exe"
      if (-not (Test-Path -LiteralPath $conda)) {
        $cmd = Get-Command conda -ErrorAction SilentlyContinue
        if ($cmd) { $conda = $cmd.Source }
      }
      if ($conda -and (Test-Path -LiteralPath $conda)) {
        & $conda clean --all -y | Out-Null
        $after = Get-SizeMB $it.Path
        $f = $it.SizeMB - $after
        if ($f -gt 0) { Write-Output ("Deleted " + $it.Label + " (-" + $f + " MB)") }
        else { Write-Output ("Nothing to clean " + $it.Label) }
        $freed += $f
      } else {
        Write-Output "Skipped conda package cache: conda.exe not found (pkgs folder NOT deleted directly)"
      }
      continue
    }
    $f = Remove-JunkItem $it
    if ($f -gt 0) { Write-Output ("Deleted " + $it.Label + " (-" + $f + " MB)") }
    else { Write-Output ("Skipped/locked " + $it.Label) }
    $freed += $f
  }
  if ($isAdmin -and $Yes) {
    foreach ($it in @($script:items | Where-Object { $_.Cat -eq "ADMIN" })) {
      $f = Remove-JunkItem $it
      if ($f -gt 0) { Write-Output ("Deleted " + $it.Label + " (-" + $f + " MB)") }
      else { Write-Output ("Skipped/locked " + $it.Label) }
      $freed += $f
    }
  } elseif ($isAdmin) {
    Write-Output "ADMIN items skipped: add -Yes to clean system caches in an elevated shell."
  } elseif (@($script:items | Where-Object { $_.Cat -eq "ADMIN" }).Count -gt 0) {
    Write-Output ""
    Write-Output "ADMIN items skipped: run this script from an elevated PowerShell to clean system caches."
  }
  Write-Output ""
  Write-Output ("Total freed: " + [math]::Round($freed / 1024, 2) + " GB")
  Write-Output ("Free C now:  " + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + " GB")
} else {
  Write-Output ""
  Write-Output "Run with -Clean to delete SAFE items; add -Yes for ASK items; elevate for ADMIN items."
}
