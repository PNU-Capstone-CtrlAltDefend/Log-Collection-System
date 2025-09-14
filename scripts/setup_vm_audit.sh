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
REPAIR_DOCKER_APT="${REPAIR_DOCKER_APT:-0}"

sanitize_docker_apt() {
  info "APT 소스 정리: download.docker.com 항목 임시 비활성화"
  local bdir="/etc/apt/sources.list.d/backup-$(date +%Y%m%d%H%M%S)"
  sudo mkdir -p "$bdir"

  mapfile -t files < <(grep -RIl "download\.docker\.com" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)
  if ((${#files[@]})); then
    for f in "${files[@]}"; do
      sudo mv -f "$f" "$bdir/" || true
      echo "  - moved: $f -> $bdir/"
    done
    warn "임시 비활성화 완료(백업: $bdir)."
  else
    echo "  - docker APT 항목 없음 → 건너뜀"
  fi

  if [[ "$REPAIR_DOCKER_APT" = "0" ]]; then
    if dpkg -l 2>/dev/null | grep -qE '^ii\s+docker-ce\s' \
       || apt-cache policy docker-ce 2>/dev/null | grep -q 'Candidate:' ; then
      warn "docker-ce 환경 감지 → Docker APT 저장소 정상 재생성(REPAIR_DOCKER_APT=1 자동 적용)."
      REPAIR_DOCKER_APT="1"
    fi
  fi

  if [[ "$REPAIR_DOCKER_APT" = "1" ]]; then
    info "Docker APT repo 정상 형태로 재생성"
    sudo install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
      if command -v curl >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
          | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
      else
        warn "curl/gpg 없음 → 키 생략(나중에 추가 권장)"
      fi
    fi
    CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    sigopt=""; [[ -f /etc/apt/keyrings/docker.gpg ]] && sigopt=" signed-by=/etc/apt/keyrings/docker.gpg"
    echo "deb [arch=$(dpkg --print-architecture)${sigopt}] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    log "docker.list 재생성 완료"
  fi
}

### 0) APT & 패키지
sanitize_docker_apt
info "apt-get update 실행"
sudo apt-get update -y
info "패키지 설치 (auditd, audispd-plugins, udisks2, udiskie, gettext-base)"
sudo apt-get install -y auditd audispd-plugins udisks2 udiskie gettext-base

### 1) auditd
info "auditd enable & start"
sudo systemctl enable auditd
sudo systemctl start auditd

### 2) udiskie 사용자 서비스/설정 배치 (전역 설정 차단 + 내 설정만)
info "udiskie 사용자 서비스/설정 배치"
mkdir -p "${HOME}/.config/systemd/user"
cat > "${HOME}/.config/systemd/user/udiskie.service" <<'EOF'
[Unit]
Description=Auto-mount USB drives via udiskie
After=udisks2.service

[Service]
Environment=XDG_CONFIG_DIRS=/dev/null
ExecStart=/usr/bin/udiskie --config %h/.config/udiskie/config.yml --automount --no-notify --no-tray
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=default.target
EOF

mkdir -p "${HOME}/.config/udiskie"
cat > "${HOME}/.config/udiskie/config.yml" <<EOF
program_options:
  automount: true
  notify: false
  tray: false

device_config:
  - automount: true
  - id_type: vfat
    options: ["rw","uid=${UIDN}","gid=${GIDN}","umask=022","flush"]
  - id_type: exfat
    options: ["rw","uid=${UIDN}","gid=${GIDN}","umask=022"]
  - id_type: ntfs
    options: ["rw","uid=${UIDN}","gid=${GIDN}","umask=022","big_writes"]
  - id_type: ext2
    options: ["rw"]
  - id_type: ext3
    options: ["rw"]
  - id_type: ext4
    options: ["rw"]
EOF

sudo loginctl enable-linger "${USER_NAME}" || true
systemctl --user daemon-reload || true
systemctl --user enable --now udiskie.service || warn "user systemd 세션 문제 시, 재로그인 후 다시 실행해 주세요."
log "udiskie 설정 완료"

### 3) 과거 충돌 규칙 정리(선택)
if [[ "${CLEANUP_LEGACY}" = "1" ]]; then
  info "과거 fstype/충돌 규칙 정리"
  if command -v docker >/dev/null 2>&1; then
    names="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'auto[-_]?device[-_]?watch' || true)"
    if [[ -n "$names" ]]; then sudo docker stop $names || true; fi
  fi
  sudo pkill -f auto_device_watch.sh 2>/dev/null || true
  sudo pkill -f 'auditctl .*fstype'   2>/dev/null || true
  sudo rm -f /etc/audit/rules.d/log_rules.rules 2>/dev/null || true
  sudo rm -rf /etc/audit/rules.d.bak.*          2>/dev/null || true
  sudo rm -f  /etc/audit/audit.rules.back.*     2>/dev/null || true
  sudo grep -RIlZ 'fstype=' /etc/audit 2>/dev/null \
    | sudo xargs -0 -r sed -i -E -- '/-F[[:space:]]*fstype=/d' || true
  sudo auditctl -D || true
  log "잔재 정리 완료"
fi

### 4) 동적 audit 규칙 스크립트 (표준 경로만, watch만)
info "update-audit-usb-rules.sh 설치"
sudo install -d -m 755 /usr/local/sbin
sudo tee /usr/local/sbin/update-audit-usb-rules.sh >/dev/null <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

RULES_D="/etc/audit/rules.d"
TMP="$RULES_D/.usb.rules.tmp"
OUT="$RULES_D/usb.rules"

mkdir -p "$RULES_D"

cat > "$TMP" <<'EOF'
-a always,exit -F arch=b64 -S mount   -F success=1 -k usb_mount
-a always,exit -F arch=b32 -S mount   -F success=1 -k usb_mount
-a always,exit -F arch=b64 -S umount2 -F success=1 -k usb_umount
-a always,exit -F arch=b32 -S umount2 -F success=1 -k usb_umount
EOF

shopt -s nullglob
for mp in /media/*/*; do
  [[ -d "$mp" ]] || continue
  esc_mp=$(printf '%s\n' "$mp" | sed 's/ /\\040/g')
  echo "-w $esc_mp -p wa -k usb_copy_watch" >> "$TMP"
done

mv -f "$TMP" "$OUT"
augenrules --load
auditctl -l | grep -E 'usb_mount|usb_umount|usb_copy_watch' || true
BASH
sudo chmod +x /usr/local/sbin/update-audit-usb-rules.sh

sudo /usr/local/sbin/update-audit-usb-rules.sh
log "규칙 초기 적용 완료 (/etc/audit/rules.d/usb.rules)"

### 5) /media 변화 자동 갱신(패스+서비스)
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
DirectoryNotEmpty=/media
PathChanged=/media
PathExistsGlob=/media/*/*
Unit=audit-usb-refresh.service

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now audit-usb-refresh.service
sudo systemctl enable --now audit-usb-refresh.path
log "자동 갱신 유닛 활성화 완료"

### 6) 상태 요약
info "규칙 스냅샷 (첫 160줄):"
sudo sed -n '1,160p' /etc/audit/rules.d/usb.rules || true

info "auditd 상태:"
sudo systemctl is-active --quiet auditd && echo "auditd: active (running)" || echo "auditd: inactive"

info "udiskie 상태:"
systemctl --user is-enabled udiskie.service || true
systemctl --user is-active  udiskie.service || true
ps -o pid,cmd -C udiskie || true

info "최근 이벤트(있으면 표시):"
sudo ausearch -k usb_mount -ts recent 2>/dev/null | tail -n +1 || true
sudo ausearch -k usb_copy_watch -ts recent 2>/dev/null | tail -n +1 || true

log "모든 단계 완료!"
