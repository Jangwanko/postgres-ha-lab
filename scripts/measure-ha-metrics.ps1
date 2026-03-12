param(
  [int]$Runs = 5
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

$reportDir = Join-Path $PSScriptRoot "..\reports"
if (-not (Test-Path $reportDir)) {
  New-Item -ItemType Directory -Path $reportDir | Out-Null
}

$results = @()
$success = 0
$totalRtoMs = 0.0
$totalRejoinMs = 0.0

for ($i = 1; $i -le $Runs; $i++) {
  Write-Host "[METRIC] run $i/$Runs"

  docker compose up -d | Out-Null
  if (-not (Wait-ForPgpool)) {
    throw "Pgpool endpoint was not ready."
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

$jsonPath = Join-Path $reportDir "ha-metrics.json"
$mdPath = Join-Path $reportDir "ha-metrics.md"

$report | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $jsonPath

$md = @(
  "# PostgreSQL HA Metrics",
  "",
  "- Runs: $Runs",
  "- Success count: $success",
  "- Success rate: $successRate%",
  "- Avg RTO: $avgRtoMs ms ($avgRtoSec sec)",
  "- Avg rejoin time: $avgRejoinMs ms ($avgRejoinSec sec)",
  "",
  "See reports/ha-metrics.json for raw results."
)
$md | Set-Content -Encoding utf8 $mdPath

Write-Host "[METRIC] done: reports/ha-metrics.json, reports/ha-metrics.md"
