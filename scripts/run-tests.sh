#!/usr/bin/env bash
set -euo pipefail

RUNS="${1:-3}"

# 단일 진입점:
# - Linux/macOS: bash 스크립트 직접 실행
# - Git Bash 등 Windows 환경: PowerShell 스크립트 우선 시도

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

echo "[RUN] docker compose up -d"
docker compose up -d >/dev/null

if [[ "$OS" == mingw* || "$OS" == msys* || "$OS" == cygwin* ]]; then
  echo "[RUN] Windows 계열 셸 감지 -> PowerShell 테스트 실행"
  powershell -ExecutionPolicy Bypass -File .\\scripts\\failover-test.ps1
  powershell -ExecutionPolicy Bypass -File .\\scripts\\measure-ha-metrics.ps1 -Runs "$RUNS"
else
  echo "[RUN] Linux/macOS 감지 -> bash 테스트 실행"
  bash ./scripts/failover-test.sh
  bash ./scripts/measure-ha-metrics.sh "$RUNS"
fi

echo "[RUN] 완료"
