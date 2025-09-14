#!/usr/bin/env bash
# cleanup-audit-auto-device-watch.sh
# - auto_device_watch 관련 컨테이너/프로세스 중지
# - audit 규칙 파일 및 fstype 규칙 정리
# - 모든 로드된 audit 규칙 제거

set -euo pipefail

# Docker 컨테이너 중지 (이름에 auto-device-watch/auto_device_watch 포함)
if command -v docker >/dev/null 2>&1; then
  docker ps --format '{{.Names}}' | grep -Ei 'auto[-_]?device[-_]?watch' >/dev/null && \
    docker stop $(docker ps --format '{{.Names}}' | grep -Ei 'auto[-_]?device[-_]?watch') || true
fi

# 관련 프로세스 정리
sudo pkill -f auto_device_watch.sh 2>/dev/null || true
sudo pkill -f 'auditctl .*fstype'   2>/dev/null || true

# 규칙 파일 제거
sudo rm -f /etc/audit/rules.d/log_rules.rules            2>/dev/null || true
sudo rm -f /host/etc/audit/rules.d/log_rules.rules       2>/dev/null || true
sudo rm -rf /etc/audit/rules.d.bak.*                     2>/dev/null || true
sudo rm -f  /etc/audit/audit.rules.back.*                2>/dev/null || true

# fstype= 이 포함된 라인 제거
sudo grep -RIlZ 'fstype=' /etc/audit /host/etc/audit 2>/dev/null \
  | sudo xargs -0 -r sed -i -E -- '/-F[[:space:]]*fstype=/d'

# 로드된 audit 규칙 전체 삭제
if command -v auditctl >/dev/null 2>&1; then
  sudo auditctl -D || true
fi

echo "Cleanup done."
