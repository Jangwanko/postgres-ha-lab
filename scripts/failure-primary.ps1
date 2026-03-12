$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

$primary = Get-CurrentPrimary
if (-not $primary) {
  throw "Primary not found."
}

Write-Host "current primary: $primary"
docker kill $primary | Out-Null
Write-Host "simulated crash on $primary"

$newPrimary = Wait-ForPrimaryChange -OldPrimary $primary -TimeoutSeconds 120 -IntervalSeconds 2
if (-not $newPrimary) {
  throw "Failover timeout."
}

Write-Host "new primary: $newPrimary"
if (-not (Wait-ForReplicaRole -Node $primary -TimeoutSeconds 180 -IntervalSeconds 2)) {
  throw "Old primary did not rejoin."
}

Write-Host "old primary rejoined as replica"
