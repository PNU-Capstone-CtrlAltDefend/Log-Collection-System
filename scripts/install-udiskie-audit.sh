#!/usr/bin/env bash
# install-udiskie-audit.sh
# - udiskie 기반 자동 마운트 (사용자 systemd 서비스)
# - /media/*/* 경로에 대한 audit 규칙 생성/적용
# 사용법: sudo bash install-udiskie-audit.sh
set -euo pipefail

### 0) 대상 사용자 식별 (sudo로 실행 시 SUDO_USER 우선)
TARGET_USER="${SUDO_USER:-$USER}"
GROUP_NAME="$(id -gn "$TARGET_USER")"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "${HOME_DIR}" || ! -d "${HOME_DIR}" ]]; then
  echo "대상 사용자 홈 디렉토리를 찾지 못했습니다: ${TARGET_USER}" >&2
  exit 1
fi
UIDN="$(id -u "$TARGET_USER")"
GIDN="$(id -g "$TARGET_USER")"

echo "[*] 대상 사용자: ${TARGET_USER} (UID=${UIDN}, GID=${GIDN})"
echo "[*] 홈 디렉토리: ${HOME_DIR}"

### 1) 패키지 설치
echo "[*] 패키지 설치: udisks2, udiskie"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y udisks2 udiskie

### 2) 사용자 systemd 서비스 생성 (udiskie)
echo "[*] 사용자 서비스 생성: udiskie"
USR_SYSD_DIR="${HOME_DIR}/.config/systemd/user"
mkdir -p "${USR_SYSD_DIR}"
cat > "${USR_SYSD_DIR}/udiskie.service" <<'EOF'
[Unit]
Description=Auto-mount USB drives via udiskie

[Service]
ExecStart=/usr/bin/udiskie -2 -a -s
Restart=on-failure

[Install]
WantedBy=default.target
EOF
chown -R "${TARGET_USER}:${GROUP_NAME}" "${HOME_DIR}/.config"
### 3) udiskie 마운트 옵션 구성 (UID/GID 반영)
echo "[*] udiskie config.yml 생성"
UDISKIE_CFG_DIR="${HOME_DIR}/.config/udiskie"
mkdir -p "${UDISKIE_CFG_DIR}"
cat > "${UDISKIE_CFG_DIR}/config.yml" <<EOF
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
chown -R "${TARGET_USER}:${GROUP_NAME}" "${UDISKIE_CFG_DIR}"

### 4) 사용자 systemd 데몬 리로드 & 서비스 활성화
echo "[*] systemd --user 데몬 리로드 및 서비스 활성화"
# linger 활성화: 로그인 세션 없이도 user 서비스 유지
loginctl enable-linger "${TARGET_USER}" || true

# 현재 세션에서 즉시 적용 시도 (세션 환경에 따라 실패할 수도 있으나, linger로 다음 로그인 시 활성화됨)
su -l "${TARGET_USER}" -c 'systemctl --user daemon-reload || true'
su -l "${TARGET_USER}" -c 'systemctl --user enable --now udiskie.service || true'

### 5) 동적 감사 규칙 스크립트 생성
echo "[*] 감사 규칙 스크립트 생성: /usr/local/sbin/update-audit-usb-rules.sh"
install -d -m 755 /usr/local/sbin
cat > /usr/local/sbin/update-audit-usb-rules.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

RULES_DIR="/etc/audit/rules.d"
RULES_FILE="${RULES_DIR}/usb.rules"

install -d -m 755 "${RULES_DIR}"

# 기본 mount/umount 감사 규칙 (성공 시)
cat > "${RULES_FILE}" <<'EOF'
-a always,exit -F arch=b64 -S mount   -F success=1 -k usb_mount
-a always,exit -F arch=b32 -S mount   -F success=1 -k usb_mount
-a always,exit -F arch=b64 -S umount2 -F success=1 -k usb_umount
-a always,exit -F arch=b32 -S umount2 -F success=1 -k usb_umount
EOF

# /media/*/* 경로에 대한 파일 오픈/생성 및 변경 감시
for mp in /media/*/*; do
  [[ -d "$mp" ]] || continue
  echo "-a always,exit -F arch=b64 -S open,openat,openat2,creat -F dir=$mp -k usb_copy_watch" >> "${RULES_FILE}"
  echo "-a always,exit -F arch=b32 -S open,openat,creat           -F dir=$mp -k usb_copy_watch" >> "${RULES_FILE}"
  echo "-w $mp -p wa -k usb_copy_watch" >> "${RULES_FILE}"
done

# 규칙 로드
if command -v augenrules >/dev/null 2>&1; then
  augenrules --load
else
  # 우분투 기본 제공. 만약 없다면 auditctl로 enable만 시도
  auditctl -e 1 || true
fi
BASH
chmod +x /usr/local/sbin/update-audit-usb-rules.sh

### 6) 감사 규칙 1회 초기 적용
echo "[*] 감사 규칙 초기 적용 실행"
/usr/local/sbin/update-audit-usb-rules.sh || true

echo
echo "✅ 완료!"
echo "- udiskie 사용자 서비스가 설정되었습니다."
echo "- /media/*/* 경로 기준으로 USB 마운트/해제 및 파일 접근 감사 규칙이 적용됩니다."
echo "- 만약 'systemctl --user'가 즉시 시작되지 않았다면, ${TARGET_USER}로 재로그인 시 자동으로 활성화됩니다(linger 적용)."
