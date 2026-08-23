<#
.SYNOPSIS
  Windows disk cleanup - scan and remove common junk/cache files safely.

.DESCRIPTION
  Categories:
    SAFE  - 100% junk, regenerated automatically
            (temp files, browser caches, crash dumps, thumbnails)
    ASK   - regenerable but possibly useful
            (package caches, updater leftovers, old app versions, recycle bin)
    ADMIN - system-level, requires an elevated shell
            (Windows Temp, Windows Update cache, ProgramData caches)

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

function Add-Item([string]$path, [string]$label, [string]$cat) {
  if (-not $path) { return }
  if (-not (Test-Path -LiteralPath $path)) { return }
  $size = Get-SizeMB $path
  if ($size -gt 0) {
    $script:items += [PSCustomObject]@{ Path = $path; Label = $label; Cat = $cat; SizeMB = $size }
  }
}

function Add-File($item, [string]$label, [string]$cat) {
  if (-not $item) { return }
  $size = Get-ItemSizeMB $item
  if ($size -gt 0) {
    $script:items += [PSCustomObject]@{ Path = $item.FullName; Label = $label; Cat = $cat; SizeMB = $size }
  }
}

$L = $env:LOCALAPPDATA
$R = $env:APPDATA

# ---------- SAFE items ----------
Add-Item (Join-Path $L "Temp") "User temp files (contents)" "SAFE"
Add-Item (Join-Path $L "CrashDumps") "Crash dumps" "SAFE"
Add-Item (Join-Path $L "Microsoft\Windows\WebCache") "WebCache (close browsers first)" "SAFE"

# Browser caches: exact folder names only, never profile data
$browserRoots = @(
  (Join-Path $L "Microsoft\Edge\User Data"),
  (Join-Path $L "Google\Chrome\User Data"),
  (Join-Path $L "BraveSoftware\Brave-Browser\User Data"),
  (Join-Path $R "Mozilla\Firefox\Profiles")
)
$cacheNames = @("Cache", "Code Cache", "GPUCache", "GrShaderCache", "ShaderCache", "DawnWebGPUCache", "cache2")
foreach ($root in $browserRoots) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $cacheNames -contains $_.Name } |
    ForEach-Object {
      $rel = $_.FullName.Substring($root.Length).TrimStart('\')
      Add-Item $_.FullName ("Browser cache: " + $rel) "SAFE"
    }
}

# Explorer thumbnail cache
$thumbDir = Join-Path $L "Microsoft\Windows\Explorer"
if (Test-Path -LiteralPath $thumbDir) {
  Get-ChildItem -LiteralPath $thumbDir -Filter "thumbcache_*.db" -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { Add-File $_ ("Thumbnail cache: " + $_.Name) "SAFE" }
}

# MATLAB ServiceHost: old versions + logs (keep the newest version)
$msh = Join-Path $L "MathWorks\ServiceHost"
if (Test-Path -LiteralPath $msh) {
  $versions = Get-ChildItem -LiteralPath $msh -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^v[\d.]+$' } |
    Sort-Object Name -Descending
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

# Recycle bin (permanent delete - only with -Yes)
$rbPath = "C:\`$Recycle.Bin"
$rbSize = Get-SizeMB $rbPath
if ($rbSize -gt 0) {
  $script:items += [PSCustomObject]@{ Path = $rbPath; Label = "Recycle Bin (permanent)"; Cat = "ASK"; SizeMB = $rbSize }
}

# Updater leftover installers: installer.exe inside *updater* folders
Get-ChildItem -LiteralPath $L -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "updater" } |
  ForEach-Object {
    Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match "^installer.*\.exe$" } |
      ForEach-Object { Add-File $_ ("Updater leftover: " + $_.Directory.Name + "\" + $_.Name) "ASK" }
  }

# Old app-* versions in launchers (keep the newest of each family)
Get-ChildItem -LiteralPath $L -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "^(app|pcr)-\d" } |
  Group-Object { $_.Name -replace "-\d[\d.]*$", "" } |
  ForEach-Object {
    $group = @($_.Group | Sort-Object Name -Descending)
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
Add-Item "C:\Windows\Temp" "Windows Temp (contents)" "ADMIN"
Add-Item "C:\Windows\SoftwareDistribution\Download" "Windows Update download cache" "ADMIN"

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
  if ($it.Label -like "*temp files*" -or $it.Label -like "*Windows Temp*") {
    Get-ChildItem -LiteralPath $it.Path -Force -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Remove-Item -LiteralPath $it.Path -Recurse -Force -ErrorAction SilentlyContinue
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
    if ($it.Label -like "Recycle Bin*") {
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
    $f = Remove-JunkItem $it
    if ($f -gt 0) { Write-Output ("Deleted " + $it.Label + " (-" + $f + " MB)") }
    else { Write-Output ("Skipped/locked " + $it.Label) }
    $freed += $f
  }
  if ($isAdmin) {
    foreach ($it in @($script:items | Where-Object { $_.Cat -eq "ADMIN" })) {
      $f = Remove-JunkItem $it
      if ($f -gt 0) { Write-Output ("Deleted " + $it.Label + " (-" + $f + " MB)") }
      else { Write-Output ("Skipped/locked " + $it.Label) }
      $freed += $f
    }
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
