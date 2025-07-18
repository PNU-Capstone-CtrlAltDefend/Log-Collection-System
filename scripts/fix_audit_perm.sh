#!/bin/bash
USER_NAME="${SUDO_USER:-$USER}"

sudo chown root:td-agent /var/log/audit
sudo chmod 750 /var/log/audit

sudo chown root:td-agent /var/log/audit/audit.log
sudo chmod 640 /var/log/audit/audit.log

sudo chown root:td-agent /etc/audit
sudo chmod 750 /etc/audit

inotifywait -m -r -e create,move "/media/$USER_NAME" --format %w%f | while read NEW_PATH; do
  if [ -e "$NEW_PATH" ]; then
    sudo chown "$USER_NAME:$USER_NAME" "$NEW_PATH"

    if [ -d "$NEW_PATH" ]; then
      chmod 755 "$NEW_PATH"
    elif [ -f "$NEW_PATH" ]; then
      chmod 644 "$NEW_PATH"
    fi
  fi
done
