param(
  [int]$Runs = 5,
  [int]$FailoverWaitSeconds = 90,
  [string]$ReportDir = "reports"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

# 운영 지표 측정 스크립트
# - RTO: Primary 장애 후 Replica 승격 완료 시간
# - 재조인 시간: old primary가 follower로 복귀 완료 시간
# - 복구 성공률: 반복 테스트 성공 비율

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
}

$results = @()
$success = 0
$totalRto = 0.0
$totalRejoin = 0.0

for ($i = 1; $i -le $Runs; $i++) {
  Write-Host "[METRIC] run $i/$Runs"

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
  }

  $rejoined = $false
  $rejoinAt = $null
  if ($promoted) {
    for ($t = 0; $t -lt 180; $t++) {
      $oldPrimaryState = ""
      try {
        $oldPrimaryState = (docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>$null).Trim()
      } catch {}
      if ($oldPrimaryState -eq "t") {
        $rejoined = $true
        $rejoinAt = Get-Date
        break
      }
      Start-Sleep -Seconds 1
    }
  }

  $rto = -1.0
  $rejoin = -1.0
  if ($promoted) {
    $rto = [Math]::Round((New-TimeSpan -Start $start -End $promoteAt).TotalSeconds, 3)
  }
  if ($rejoined) {
    $rejoin = [Math]::Round((New-TimeSpan -Start $promoteAt -End $rejoinAt).TotalSeconds, 3)
    $success++
    $totalRto += $rto
    $totalRejoin += $rejoin
  }

  $results += [pscustomobject]@{
    run            = $i
    rto_seconds    = $rto
    rejoin_seconds = $rejoin
    success        = $rejoined
  }
}

$successRate = if ($Runs -gt 0) { [Math]::Round(($success / $Runs) * 100, 2) } else { 0 }
$avgRto = if ($success -gt 0) { [Math]::Round($totalRto / $success, 3) } else { 0 }
$avgRejoin = if ($success -gt 0) { [Math]::Round($totalRejoin / $success, 3) } else { 0 }

$report = [pscustomobject]@{
  runs                 = $Runs
  success_count        = $success
  success_rate_percent = $successRate
  avg_rto_seconds      = $avgRto
  avg_rejoin_seconds   = $avgRejoin
  results              = $results
}

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

$md = @(
  "# HA Metrics Report",
  "",
  "- Runs: $Runs",
  "- Success count: $success",
  "- Success rate: $successRate%",
  "- Avg RTO (promotion complete): $avgRto sec",
  "- Avg rejoin time (old primary to follower): $avgRejoin sec",
  "",
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

$promDir = "reports-fixed"
if (!(Test-Path $promDir)) {
  New-Item -ItemType Directory -Path $promDir | Out-Null
}
$promPath = Join-Path $promDir "ha-metrics.prom"
$promPayload = ($promLines -join "`n") + "`n"
[IO.File]::WriteAllBytes($promPath, [Text.Encoding]::ASCII.GetBytes($promPayload))

Write-Host "[METRIC] done: $reportJsonPath, $reportMdPath"
Write-Host ("[METRIC] summary: runs={0}, success={1}/{2} ({3}%), avg_rto={4}s, avg_rejoin={5}s" -f $Runs,$success,$Runs,$successRate,$avgRto,$avgRejoin)
