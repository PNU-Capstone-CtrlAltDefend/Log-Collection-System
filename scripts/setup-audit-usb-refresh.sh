#!/usr/bin/env bash
set -e

# === audit-usb-refresh.service ===
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

# === audit-usb-refresh.path ===
sudo tee /etc/systemd/system/audit-usb-refresh.path >/dev/null <<'UNIT'
[Unit]
Description=Watch /media for USB mountpoints

[Path]
DirectoryNotEmpty=/media
Unit=audit-usb-refresh.service

[Install]
WantedBy=multi-user.target
UNIT

# === systemd reload & enable ===
sudo systemctl daemon-reload
sudo systemctl enable --now audit-usb-refresh.service
sudo systemctl enable --now audit-usb-refresh.path

echo "✅ audit-usb-refresh systemd units installed and enabled."
