# One-time setup on the desktop (normal PowerShell, not admin).
$dir = "C:\gpu-worker"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements; $env:Path += ";C:\Program Files\Git\cmd" }
if (-not (Test-Path $dir)) { git clone https://github.com/teddywasserman/gpu-worker $dir }
Set-Location $dir
git config user.name "gpu-worker"; git config user.email "teddywasserman@users.noreply.github.com"
$a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\worker.ps1`""
$t = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "GpuWorker" -Action $a -Trigger $t -Settings $s -Force | Out-Null
Start-ScheduledTask -TaskName "GpuWorker"
"GPU worker installed and started."
