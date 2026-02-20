$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

# 종단 간(E2E) 검증 스크립트:
# 1) primary 중지
# 2) replica 자동 승격 확인
# 3) primary 자동 재기동 및 follower 재조인 확인
Write-Host "Stopping primary to simulate failure..."
docker stop pg_primary | Out-Null

Write-Host "Waiting for automatic failover (replica promotion)..."
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  $state = ""
  try {
    $state = (docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>$null).Trim()
  } catch {}
  $leader = (Get-Content .\cluster-state\current_primary -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
  if ($state -eq "f" -and $leader -eq "replica") {
    $ok = $true
    break
  }
  Start-Sleep -Seconds 2
}

if (-not $ok) {
  throw "Failover did not complete in time."
}

Write-Host "Waiting for automatic primary restart and resync as follower..."

for ($i = 0; $i -lt 90; $i++) {
  $oldPrimaryState = ""
  try {
    $oldPrimaryState = (docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>$null).Trim()
  } catch {}
  $leader = (Get-Content .\cluster-state\current_primary -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
  if ($oldPrimaryState -eq "t" -and $leader -eq "replica") {
    Write-Host "Failback complete: old primary is now follower."
    exit 0
  }
  Start-Sleep -Seconds 2
}

throw "Failback did not complete in time."
