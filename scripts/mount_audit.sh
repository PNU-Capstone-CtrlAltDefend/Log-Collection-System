#!/bin/bash

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME="/home/$USER_NAME"
BASE_MEDIA="/media/$USER_NAME"

inotifywait -m -e create "$USER_HOME" --format "%w%f" | while read FILE_PATH; do
  if [[ "$FILE_PATH" == *.img ]]; then
    IMG_ABS_PATH=$(realpath "$FILE_PATH")
    IMG_NAME=$(basename "$FILE_PATH" .img)
    MOUNT_DIR="$BASE_MEDIA/$IMG_NAME"

    echo "📦 새 .img 감지: $IMG_NAME → 마운트 준비"

    sudo mkdir -p "$MOUNT_DIR"
    sudo mount -o loop,uid=$(id -u "$USER_NAME"),gid=$(id -g "$USER_NAME") "$IMG_ABS_PATH" "$MOUNT_DIR"
    sudo chown -R "$USER_NAME:$USER_NAME" "$MOUNT_DIR"
    sudo auditctl -w "$MOUNT_DIR" -p wa -k usb_copy

    echo "✅ 마운트 및 audit 감시 완료: $MOUNT_DIR"
  fi
done
