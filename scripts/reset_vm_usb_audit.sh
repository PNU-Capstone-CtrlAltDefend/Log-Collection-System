#!/usr/bin/env bash
set -euo pipefail

info(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }

DRY="${DRY_RUN:-0}"
PURGE="${PURGE_PACKAGES:-0}"

run(){ if [ "$DRY" = "1" ]; then echo "[DRY] $*"; else eval "$@"; fi }

info "1) systemd 유닛 비활성화 및 삭제"
run 'sudo systemctl disable --now audit-usb-refresh.path 2>/dev/null || true'
run 'sudo systemctl disable --now audit-usb-refresh.service 2>/dev/null || true'
run 'sudo rm -f /etc/systemd/system/audit-usb-refresh.path /etc/systemd/system/audit-usb-refresh.service'
run 'sudo systemctl daemon-reload'

info "2) audit 규칙/백업/잔재 제거"
run 'sudo rm -f /etc/audit/rules.d/usb.rules /etc/audit/rules.usb.rules'
run 'sudo rm -rf /etc/audit/rules.d.bak.*'
run 'sudo rm -f /etc/audit/audit.rules.back.*'
run "sudo grep -RIlZ 'fstype=' /etc/audit 2>/dev/null | sudo xargs -0 -r sed -i -E -- '/-F[[:space:]]*fstype=/d' || true"

info "3) 실시간 규칙 초기화"
run 'sudo auditctl -D || true'

info "4) udiskie 사용자 설정/서비스 제거(사용자 홈)"
run 'rm -f ~/.config/systemd/user/udiskie.service'
run 'rm -f ~/.config/udiskie/config.yml'
run 'systemctl --user daemon-reload || true'
run 'systemctl --user disable --now udiskie.service 2>/dev/null || true'

info "5) linger 해제(선택)"
run 'sudo loginctl disable-linger "$USER" || true'

if [ "$PURGE" = "1" ]; then
  info "6) 패키지 제거(auditd, audispd-plugins, udiskie, udisks2)"
  run 'sudo apt-get purge -y auditd audispd-plugins udiskie udisks2 || true'
  run 'sudo apt-get autoremove -y || true'
fi

ok "초기화 완료. 재부팅을 권장합니다."
echo "다시 테스트하려면: ./setup_vm_usb_audit.sh"
