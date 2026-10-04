# GPU worker: pulls jobs from this private repo, runs them, pushes results back.
# Outbound only (git over HTTPS), so no inbound ports/SSH are needed.
# Job file: jobs/<id>.json  {"id":"...", "cmd":"<powershell command>", "cwd":"C:\gpu-work", "timeout_min":60}
$ErrorActionPreference = "Continue"
# Scheduled tasks may start with a stale PATH right after Git was installed: use full paths.
foreach ($g in @("C:\Program Files\Git\cmd\git.exe", "C:\Program Files (x86)\Git\cmd\git.exe")) { if (Test-Path $g) { Set-Alias -Name git -Value $g -Scope Script; break } }
$env:Path += ";C:\Windows\System32;C:\Program Files\NVIDIA Corporation\NVSMI"
Start-Transcript -Path (Join-Path $env:TEMP "gpu-worker.log") -Append | Out-Null
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo
$lastBeat = Get-Date "2000-01-01"
function Sync { git pull --rebase --quiet 2>&1 | Out-Null }
function Push($msg) {
  git add -A results status 2>&1 | Out-Null
  git commit -q -m $msg 2>&1 | Out-Null
  for ($i = 0; $i -lt 3; $i++) { git push --quiet 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { break }; git pull --rebase --quiet 2>&1 | Out-Null }
}
while ($true) {
  try {
    Sync
    if (((Get-Date) - $lastBeat).TotalMinutes -ge 15) {
      $gpu = (& nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader 2>&1) -join "; "
      @{ host = $env:COMPUTERNAME; time = (Get-Date).ToString("s"); gpu = $gpu } | ConvertTo-Json | Set-Content -Encoding utf8 status/heartbeat.json
      Push "heartbeat"; $lastBeat = Get-Date
    }
    foreach ($f in Get-ChildItem jobs -Filter *.json -ErrorAction SilentlyContinue) {
      $job = Get-Content $f.FullName -Raw | ConvertFrom-Json
      $out = Join-Path "results" $job.id
      if (Test-Path $out) { continue }
      New-Item -ItemType Directory -Force $out | Out-Null
      @{ id = $job.id; state = "running"; started = (Get-Date).ToString("s") } | ConvertTo-Json | Set-Content -Encoding utf8 "$out/status.json"
      Push "start $($job.id)"
      $cwd = if ($job.cwd) { $job.cwd } else { "C:\gpu-work" }
      New-Item -ItemType Directory -Force $cwd | Out-Null
      $log = Join-Path $repo "$out/log.txt"
      $tmo = if ($job.timeout_min) { [int]$job.timeout_min } else { 60 }
      $p = Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-Command","Set-Location '$cwd'; $($job.cmd) *>&1 | Out-File -Encoding utf8 '$log'" -PassThru -WindowStyle Hidden
      $done = $p.WaitForExit($tmo * 60 * 1000)
      if (-not $done) { Stop-Process -Id $p.Id -Force; $code = "timeout" } else { $code = $p.ExitCode }
      if ((Get-Item $log -ErrorAction SilentlyContinue).Length -gt 900KB) { $t = Get-Content $log -Tail 3000; $t | Set-Content -Encoding utf8 $log }
      @{ id = $job.id; state = "done"; exit = "$code"; finished = (Get-Date).ToString("s") } | ConvertTo-Json | Set-Content -Encoding utf8 "$out/status.json"
      Push "done $($job.id)"
    }
  } catch { }
  Start-Sleep 30
}
