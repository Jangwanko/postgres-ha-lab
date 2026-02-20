param(
  [int]$Runs = 5
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

# 운영 지표 측정 스크립트
# - RTO: Primary 장애 후 Replica 승격 완료 시간
# - 재조인 시간: old primary가 follower로 복귀 완료 시간
# - 복구 성공률: 반복 테스트 성공 비율

$reportDir = "reports"
if (!(Test-Path $reportDir)) {
  New-Item -ItemType Directory -Path $reportDir | Out-Null
}

$results = @()
$success = 0
$totalRto = 0.0
$totalRejoin = 0.0

for ($i = 1; $i -le $Runs; $i++) {
  Write-Host "[METRIC] run $i/$Runs"

  docker compose up -d | Out-Null
  Start-Sleep -Seconds 2

  $start = Get-Date
  docker stop pg_primary | Out-Null

  $promoted = $false
  $promoteAt = $null
  for ($t = 0; $t -lt 90; $t++) {
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

$report | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 .\reports\ha-metrics.json

$md = @(
  "# HA Metrics Report",
  "",
  "- Runs: $Runs",
  "- Success count: $success",
  "- Success rate: $successRate%",
  "- Avg RTO (promotion complete): $avgRto sec",
  "- Avg rejoin time (old primary to follower): $avgRejoin sec",
  "",
  "Raw data: reports/ha-metrics.json"
)
$md | Set-Content -Encoding utf8 .\reports\ha-metrics.md

Write-Host "[METRIC] done: reports/ha-metrics.json, reports/ha-metrics.md"
