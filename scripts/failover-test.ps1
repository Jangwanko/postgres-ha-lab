$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

Write-Host "[TEST] waiting for Pgpool endpoint..."
if (-not (Wait-ForPgpool)) {
  throw "Pgpool endpoint is not ready."
}

$oldPrimary = Get-CurrentPrimary
if (-not $oldPrimary) {
  throw "Current primary was not detected."
}

Write-Host "[TEST] current primary: $oldPrimary"
Write-Host "[TEST] simulating primary crash..."
docker kill $oldPrimary | Out-Null

Write-Host "[TEST] waiting for automatic failover..."
$newPrimary = Wait-ForPrimaryChange -OldPrimary $oldPrimary -TimeoutSeconds 120 -IntervalSeconds 2
if (-not $newPrimary) {
  throw "No new primary elected within timeout."
}

Write-Host "[TEST] new primary elected: $newPrimary"
Write-Host "[TEST] running controlled rejoin for old primary..."
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\rejoin-node.ps1" -Node $oldPrimary | Out-Null

Write-Host "[TEST] waiting for old primary to rejoin as replica..."
if (-not (Wait-ForReplicaRole -Node $oldPrimary -TimeoutSeconds 240 -IntervalSeconds 2)) {
  throw "Old primary did not return as replica after rejoin."
}

if (-not (Wait-ForPgpool)) {
  throw "Pgpool did not recover after failover."
}

Write-Host "[TEST] cluster recovered successfully"
