param(
  [int]$Runs = 3
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

# 단일 진입점:
# - Windows: PowerShell 스크립트 사용
# - Linux/macOS(PowerShell Core): bash 스크립트 사용

$isWindowsHost = $env:OS -eq "Windows_NT"

Write-Host "[RUN] docker compose up -d"
docker compose up -d | Out-Null
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed with exit code $LASTEXITCODE" }

if ($isWindowsHost) {
  Write-Host "[RUN] Windows 환경 감지 -> PowerShell 테스트 실행"
  powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1
  if ($LASTEXITCODE -ne 0) { throw "failover-test.ps1 failed with exit code $LASTEXITCODE" }

  powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs $Runs
  if ($LASTEXITCODE -ne 0) { throw "measure-ha-metrics.ps1 failed with exit code $LASTEXITCODE" }
} else {
  Write-Host "[RUN] 비-Windows 환경 감지 -> bash 테스트 실행"
  bash ./scripts/failover-test.sh
  if ($LASTEXITCODE -ne 0) { throw "failover-test.sh failed with exit code $LASTEXITCODE" }

  bash ./scripts/measure-ha-metrics.sh $Runs
  if ($LASTEXITCODE -ne 0) { throw "measure-ha-metrics.sh failed with exit code $LASTEXITCODE" }
}

Write-Host "[RUN] 완료"
