# clean-hidden-photoshop.ps1 - kill hidden, idle Photoshop instances.
# Pure ASCII. Only processes with no main window, older than 10 minutes,
# and less than 0.5s CPU over a 5s sample are touched.
param(
  [switch]$DryRun,
  [switch]$Install,
  [switch]$Uninstall
)

$ErrorActionPreference = 'SilentlyContinue'
$scriptPath = $MyInvocation.MyCommand.Path
$logPath = Join-Path (Split-Path -Parent $scriptPath) 'clean-hidden-photoshop.log'
$taskName = 'CleanHiddenPhotoshop'

function Write-Log([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
  Add-Content -LiteralPath $logPath -Value $line -Encoding ASCII
  if ((Get-Item -LiteralPath $logPath).Length -gt 1MB) {
    $tail = @(Get-Content -LiteralPath $logPath | Select-Object -Last 200)
    Set-Content -LiteralPath $logPath -Value $tail -Encoding ASCII
  }
}

if ($Uninstall) {
  schtasks /Delete /TN $taskName /F | Out-Null
  Write-Output "Removed scheduled task: $taskName"
  exit 0
}

if ($Install) {
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '"')
  $trigger = New-ScheduledTaskTrigger -Daily -At '00:00'
  $rep = New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 1)
  $trigger.Repetition = $rep.Repetition
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
  Write-Output "Installed: $taskName (every 30 min, daily)"
  exit 0
}

$now = Get-Date
$targets = @(Get-Process -Name Photoshop -ErrorAction SilentlyContinue | Where-Object {
  $_.MainWindowHandle -eq 0 -and (($now - $_.StartTime).TotalMinutes -ge 10)
})
if ($targets.Count -eq 0) { exit 0 }

$before = @{}
foreach ($p in $targets) { $before[$p.Id] = $p.CPU }
Start-Sleep -Seconds 5

foreach ($p in $targets) {
  $cur = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
  if (-not $cur) { continue }
  if ($cur.MainWindowHandle -ne 0) { continue }
  $delta = $cur.CPU - $before[$p.Id]
  if ($null -eq $delta -or $delta -gt 0.5) { continue }
  $desc = "pid=$($p.Id) ageMin=$([math]::Round((($now - $p.StartTime).TotalMinutes),0)) privMB=$([math]::Round($p.PrivateMemorySize64/1MB,0))"
  if ($DryRun) { Write-Output "Would kill $desc"; continue }
  Stop-Process -Id $p.Id -Force
  Start-Sleep -Milliseconds 500
  if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) {
    Write-Log "STUCK $desc (reboot required)"
  } else {
    Write-Log "KILLED $desc"
  }
}