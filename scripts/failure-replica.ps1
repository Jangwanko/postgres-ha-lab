$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot\ha-common.ps1"

$replica = Get-CurrentReplicas | Select-Object -First 1
if (-not $replica) {
  throw "Replica not found."
}

Write-Host "current replica: $replica"
docker kill $replica | Out-Null
Write-Host "simulated crash on $replica"

if (-not (Wait-ForReplicaRole -Node $replica -TimeoutSeconds 180 -IntervalSeconds 2)) {
  throw "Replica did not return to recovery mode."
}

Write-Host "replica recovered and rejoined"
