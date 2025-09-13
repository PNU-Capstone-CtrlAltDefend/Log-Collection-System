#!/usr/bin/env bash
set -euo pipefail

log()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }

USER_NAME="${USER}"
UIDN="$(id -u)"
GIDN="$(id -g)"

CLEANUP_LEGACY="${CLEANUP_LEGACY:-1}"

info "패키지 설치 (auditd, audispd-plugins, udisks2, udiskie, gettext-base)"
sudo apt-get update -y
sudo apt-get install -y auditd audispd-plugins udisks2 udiskie gettext-base || true

info "auditd enable & start"
sudo systemctl enable auditd
sudo systemctl start auditd

info "udiskie 사용자 서비스/설정 배치"
mkdir -p "${HOME}/.config/systemd/user"
cat > "${HOME}/.config/systemd/user/udiskie.service" <<'EOF'
[Unit]
Description=Auto-mount USB drives via udiskie

[Service]
ExecStart=/usr/bin/udiskie -2 -a -s
Restart=on-failure

[Install]
WantedBy=default.target
EOF

mkdir -p "${HOME}/.config/udiskie"
cat > "${HOME}/.config/udiskie/config.yml" <<EOF
mount_options:
  vfat:  [rw,uid=${UIDN},gid=${GIDN},umask=022,flush]
  exfat: [rw,uid=${UIDN},gid=${GIDN},umask=022]
  ntfs:  [rw,uid=${UIDN},gid=${GIDN},umask=022,big_writes]
  ext2:  [rw]
  ext3:  [rw]
  ext4:  [rw]
device_config:
  default_options: { automount: true }
EOF

sudo loginctl enable-linger "${USER_NAME}" || true
systemctl --user daemon-reload || true
systemctl --user enable --now udiskie.service || warn "user systemd 세션 문제 시, 재로그인 후 다시 실행해 주세요."
log "udiskie 설정 완료"

if [[ "${CLEANUP_LEGACY}" = "1" ]]; then
  info "과거 fstype/충돌 규칙 정리"
  if command -v docker >/dev/null 2>&1; then
    docker ps --format '{{.Names}}' | grep -Ei 'auto[-_]?device[-_]?watch' >/dev/null && \
    sudo docker stop $(docker ps --format '{{.Names}}' | grep -Ei 'auto[-_]?device[-_]?watch') || true
  fi
  sudo pkill -f auto_device_watch.sh 2>/dev/null || true
  sudo pkill -f 'auditctl .*fstype'   2>/dev/null || true

  sudo rm -f /etc/audit/rules.d/log_rules.rules 2>/dev/null || true
  sudo rm -rf /etc/audit/rules.d.bak.*          2>/dev/null || true
  sudo rm -f  /etc/audit/audit.rules.back.*     2>/dev/null || true

  sudo grep -RIlZ 'fstype=' /etc/audit 2>/dev/null \
    | sudo xargs -0 -r sed -i -E -- '/-F[[:space:]]*fstype=/d'

  sudo auditctl -D || true
  log "잔재 정리 완료"
fi

info "update-audit-usb-rules.sh 설치"
sudo install -d -m 755 /usr/local/sbin
sudo tee /usr/local/sbin/update-audit-usb-rules.sh >/dev/null <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

RULES_D="/etc/audit/rules.d"
MAIN_RULES="$RULES_D/usb.rules"

mkdir -p "$RULES_D"

cat > "$MAIN_RULES" <<'EOF'
-a always,exit -F arch=b64 -S mount   -F success=1 -k usb_mount
-a always,exit -F arch=b32 -S mount   -F success=1 -k usb_mount
-a always,exit -F arch=b64 -S umount2 -F success=1 -k usb_umount
-a always,exit -F arch=b32 -S umount2 -F success=1 -k usb_umount
EOF

shopt -s nullglob
for mp in /media/*/*; do
  [[ -d "$mp" ]] || continue
  echo "-a always,exit -F arch=b64 -S open,openat,openat2,creat -F dir=$mp -k usb_copy_watch" >> "$MAIN_RULES"
  echo "-a always,exit -F arch=b32 -S open,openat,creat -F dir=$mp -k usb_copy_watch"        >> "$MAIN_RULES"
  echo "-w $mp -p wa -k usb_copy_watch"                                                      >> "$MAIN_RULES"
done

command -v augenrules >/dev/null 2>&1 && augenrules --load || true
command -v auditctl  >/dev/null 2>&1 && auditctl -e 1      || true

echo "[update-audit-usb-rules] rules updated & applied"
BASH
sudo chmod +x /usr/local/sbin/update-audit-usb-rules.sh

sudo /usr/local/sbin/update-audit-usb-rules.sh
log "규칙 초기 적용 완료 (/etc/audit/rules.d/usb.rules)"

info "systemd .service/.path 유닛 배치"

sudo tee /etc/systemd/system/audit-usb-refresh.service >/dev/null <<'UNIT'
[Unit]
Description=Refresh audit USB rules on mount changes
After=auditd.service local-fs.target
Wants=auditd.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash /usr/local/sbin/update-audit-usb-rules.sh

[Install]
WantedBy=multi-user.target
UNIT

sudo tee /etc/systemd/system/audit-usb-refresh.path >/dev/null <<'UNIT'
[Unit]
Description=Watch /media for USB mountpoints

[Path]
PathExistsGlob=/media/*/*
Unit=audit-usb-refresh.service

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now audit-usb-refresh.service
sudo systemctl enable --now audit-usb-refresh.path
log "자동 갱신 유닛 활성화 완료"

info "규칙 스냅샷 (첫 160줄):"
sudo sed -n '1,160p' /etc/audit/rules.d/usb.rules || true

info "auditd 상태:"
sudo systemctl is-active --quiet auditd && echo "auditd: active (running)" || echo "auditd: inactive"

info "최근 이벤트(있으면 표시):"
sudo ausearch -k usb_mount -ts recent 2>/dev/null | tail -n +1 || true
sudo ausearch -k usb_copy_watch -ts recent 2>/dev/null | tail -n +1 || true

log "모든 단계 완료!"
