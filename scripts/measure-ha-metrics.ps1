param(
  [int]$Runs = 5,
  [int]$FailoverWaitSeconds = 90,
  [string]$ReportDir = "reports"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

<<<<<<< HEAD
if (!(Test-Path $ReportDir)) {
  New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

# If reports dir is not writable, fall back to a local writable dir.
try {
  $testPath = Join-Path $ReportDir ".write_test"
  "ok" | Set-Content -Encoding utf8 $testPath
  Remove-Item -Force $testPath
} catch {
  $ReportDir = "reports-fixed"
  if (!(Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
  }
=======
$reportDir = Join-Path $PSScriptRoot "..\reports"
if (-not (Test-Path $reportDir)) {
  New-Item -ItemType Directory -Path $reportDir | Out-Null
>>>>>>> 256d885e1487bea6ff565c61f3d7adb05d0e1dae
}

$results = @()
$success = 0
$totalRtoMs = 0.0
$totalRejoinMs = 0.0

for ($i = 1; $i -le $Runs; $i++) {
  Write-Host "[METRIC] run $i/$Runs"

<<<<<<< HEAD
  try {
    docker start pg_primary pg_replica pg_failover_manager | Out-Null
  } catch {}
  Start-Sleep -Seconds 2

  $start = Get-Date
  docker stop pg_primary | Out-Null

  $promoted = $false
  $promoteAt = $null
  for ($t = 0; $t -lt $FailoverWaitSeconds; $t++) {
    $state = ""
    try {
      $state = (docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>$null).Trim()
    } catch {}

    $leader = ""
    try {
      $leader = (Get-Content .\cluster-state\current_primary -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    } catch {}

    if ($state -eq "f" -and $leader -eq "replica") {
      $promoted = $true
      $promoteAt = Get-Date
      break
    }
    Start-Sleep -Seconds 1
=======
  docker compose up -d | Out-Null
  if (-not (Wait-ForPgpool)) {
    throw "Pgpool endpoint was not ready."
>>>>>>> 256d885e1487bea6ff565c61f3d7adb05d0e1dae
  }

  $oldPrimary = Get-CurrentPrimary
  if (-not $oldPrimary) {
    throw "Current primary was not detected."
  }

  $start = [DateTimeOffset]::UtcNow
  docker kill $oldPrimary | Out-Null

  $newPrimary = Wait-ForPrimaryChange -OldPrimary $oldPrimary -TimeoutSeconds 120 -IntervalSeconds 1
  $promotedAt = $null
  if ($newPrimary) {
    $promotedAt = [DateTimeOffset]::UtcNow
  }

  $rejoinedAt = $null
  $rejoined = $false
  if ($newPrimary) {
    powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\rejoin-node.ps1" -Node $oldPrimary | Out-Null
    $rejoined = Wait-ForReplicaRole -Node $oldPrimary -TimeoutSeconds 240 -IntervalSeconds 1
    if ($rejoined) {
      $rejoinedAt = [DateTimeOffset]::UtcNow
    }
  }

  $rtoMs = -1
  $rejoinMs = -1
  $ok = $false
  if ($promotedAt) {
    $rtoMs = [Math]::Round(($promotedAt - $start).TotalMilliseconds, 0)
  }
  if ($rejoined -and $rejoinedAt) {
    $rejoinMs = [Math]::Round(($rejoinedAt - $promotedAt).TotalMilliseconds, 0)
    $ok = $true
    $success++
    $totalRtoMs += $rtoMs
    $totalRejoinMs += $rejoinMs
  }

  $results += [pscustomobject]@{
    run           = $i
    failed_node   = $oldPrimary
    promoted_node = $newPrimary
    rto_ms        = $rtoMs
    rejoin_ms     = $rejoinMs
    success       = $ok
  }
}

$successRate = if ($Runs -gt 0) { [Math]::Round(($success / $Runs) * 100, 2) } else { 0 }
$avgRtoMs = if ($success -gt 0) { [Math]::Round($totalRtoMs / $success, 2) } else { 0 }
$avgRejoinMs = if ($success -gt 0) { [Math]::Round($totalRejoinMs / $success, 2) } else { 0 }
$avgRtoSec = [Math]::Round($avgRtoMs / 1000, 3)
$avgRejoinSec = [Math]::Round($avgRejoinMs / 1000, 3)

$report = [pscustomobject]@{
  runs                 = $Runs
  success_count        = $success
  success_rate_percent = $successRate
  avg_rto_ms           = $avgRtoMs
  avg_rto_seconds      = $avgRtoSec
  avg_rejoin_ms        = $avgRejoinMs
  avg_rejoin_seconds   = $avgRejoinSec
  results              = $results
}

<<<<<<< HEAD
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$promLines = @(
  "# HELP ha_runs_total Total HA test runs",
  "# TYPE ha_runs_total gauge",
  ("ha_runs_total {0}" -f $Runs),
  "# HELP ha_success_count Successful HA test runs",
  "# TYPE ha_success_count gauge",
  ("ha_success_count {0}" -f $success),
  "# HELP ha_success_rate_percent Success rate in percent",
  "# TYPE ha_success_rate_percent gauge",
  ("ha_success_rate_percent {0}" -f ([string]::Format($inv, "{0}", $successRate))),
  "# HELP ha_rto_seconds_avg Average failover RTO in seconds",
  "# TYPE ha_rto_seconds_avg gauge",
  ("ha_rto_seconds_avg {0}" -f ([string]::Format($inv, "{0}", $avgRto))),
  "# HELP ha_rejoin_seconds_avg Average rejoin time in seconds",
  "# TYPE ha_rejoin_seconds_avg gauge",
  ("ha_rejoin_seconds_avg {0}" -f ([string]::Format($inv, "{0}", $avgRejoin))),
  "# HELP ha_last_run_timestamp_seconds Unix timestamp of last measurement",
  "# TYPE ha_last_run_timestamp_seconds gauge",
  ("ha_last_run_timestamp_seconds {0}" -f ([int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))
)

$reportJsonPath = Join-Path $ReportDir "ha-metrics.json"
$reportMdPath = Join-Path $ReportDir "ha-metrics.md"

$writeReport = {
  param($JsonPath, $MdPath, $MdLines, $ReportObj)
  $ReportObj | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $JsonPath
  $MdLines | Set-Content -Encoding utf8 $MdPath
}
=======
$jsonPath = Join-Path $reportDir "ha-metrics.json"
$mdPath = Join-Path $reportDir "ha-metrics.md"

$report | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $jsonPath
>>>>>>> 256d885e1487bea6ff565c61f3d7adb05d0e1dae

$md = @(
  "# PostgreSQL HA Metrics",
  "",
  "- Runs: $Runs",
  "- Success count: $success",
  "- Success rate: $successRate%",
  "- Avg RTO: $avgRtoMs ms ($avgRtoSec sec)",
  "- Avg rejoin time: $avgRejoinMs ms ($avgRejoinSec sec)",
  "",
<<<<<<< HEAD
  "Raw data: $reportJsonPath"
)
try {
  & $writeReport $reportJsonPath $reportMdPath $md $report
} catch {
  $ReportDir = "reports-fixed"
  if (!(Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
  }
  $reportJsonPath = Join-Path $ReportDir "ha-metrics.json"
  $reportMdPath = Join-Path $ReportDir "ha-metrics.md"
  & $writeReport $reportJsonPath $reportMdPath $md $report
}
=======
  "See reports/ha-metrics.json for raw results."
)
$md | Set-Content -Encoding utf8 $mdPath
>>>>>>> 256d885e1487bea6ff565c61f3d7adb05d0e1dae

$promDir = "reports-fixed"
if (!(Test-Path $promDir)) {
  New-Item -ItemType Directory -Path $promDir | Out-Null
}
$promPath = Join-Path $promDir "ha-metrics.prom"
$promPayload = ($promLines -join "`n") + "`n"
[IO.File]::WriteAllBytes($promPath, [Text.Encoding]::ASCII.GetBytes($promPayload))

Write-Host "[METRIC] done: $reportJsonPath, $reportMdPath"
Write-Host ("[METRIC] summary: runs={0}, success={1}/{2} ({3}%), avg_rto={4}s, avg_rejoin={5}s" -f $Runs,$success,$Runs,$successRate,$avgRto,$avgRejoin)
