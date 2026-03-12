param(
  [Parameter(Mandatory = $true)]
  [string]$Node
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

$serviceName = Get-ServiceNameFromNode -Node $Node
$volumeName = Get-VolumeNameFromNode -Node $Node
$currentPrimary = Get-CurrentPrimary

if ($currentPrimary -and $currentPrimary -eq $Node) {
  throw "Target node is current primary."
}

Write-Host "[REJOIN] target node: $Node"
Write-Host "[REJOIN] service: $serviceName"
Write-Host "[REJOIN] removing old data volume: $volumeName"

docker stop $Node *> $null
docker rm -f $Node *> $null
docker volume rm $volumeName *> $null

$overrideVar = $null
switch ($Node) {
  "pg_node1" { $overrideVar = "REPMGR_PRIMARY_HOST_NODE1" }
  "pg_node2" { $overrideVar = "REPMGR_PRIMARY_HOST_NODE2" }
  "pg_node3" { $overrideVar = "REPMGR_PRIMARY_HOST_NODE3" }
}

if ($currentPrimary -and $overrideVar) {
  $currentPrimaryService = Get-ServiceNameFromNode -Node $currentPrimary
  Set-Item -Path "Env:$overrideVar" -Value $currentPrimaryService
}

try {
  docker compose up -d $serviceName | Out-Null
} finally {
  if ($overrideVar -and (Test-Path "Env:$overrideVar")) {
    Remove-Item "Env:$overrideVar"
  }
}

if (-not (Wait-ForReplicaRole -Node $Node -TimeoutSeconds 240 -IntervalSeconds 2)) {
  throw "Node did not return as replica."
}

Write-Host "[REJOIN] node rejoined as replica"
