param(
  [int]$Runs = 3
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "[RUN] starting PostgreSQL HA stack"
docker compose up -d | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "docker compose up failed with exit code $LASTEXITCODE"
}

Write-Host "[RUN] failover test"
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\failover-test.ps1"
if ($LASTEXITCODE -ne 0) {
  throw "failover-test.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "[RUN] metric measurement"
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\measure-ha-metrics.ps1" -Runs $Runs
if ($LASTEXITCODE -ne 0) {
  throw "measure-ha-metrics.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "[RUN] completed"
