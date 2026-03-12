$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

$primary = Get-CurrentPrimary
if (-not $primary) {
  throw "Primary not found."
}

Write-Host "disconnecting $primary from $script:ClusterNetwork"
docker network disconnect $script:ClusterNetwork $primary | Out-Null

try {
  $newPrimary = Wait-ForPrimaryChange -OldPrimary $primary -TimeoutSeconds 120 -IntervalSeconds 2
  if (-not $newPrimary) {
    throw "Failover timeout during network partition."
  }

  Write-Host "new primary after partition: $newPrimary"
} finally {
  docker network connect $script:ClusterNetwork $primary *> $null
}

if (-not (Wait-ForReplicaRole -Node $primary -TimeoutSeconds 180 -IntervalSeconds 2)) {
  throw "Isolated node did not rejoin as replica."
}

Write-Host "network partition recovered"
