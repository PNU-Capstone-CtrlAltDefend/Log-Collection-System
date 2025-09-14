#!/usr/bin/env bash
set -e

echo "=== 🔹 Docker & Docker Compose 설치 시작 ==="

# 1. 필수 패키지
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# 2. GPG key 추가
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Docker 공식 리포지토리 추가
UBUNTU_CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Docker 설치
sudo apt-get update
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# 5. 현재 사용자 docker 그룹 추가
sudo usermod -aG docker $USER

# 6. 서비스 활성화
sudo systemctl enable --now docker

echo "=== ✅ 설치 완료 ==="
echo "로그아웃 후 다시 로그인하거나 'newgrp docker' 실행해야 docker 그룹 권한이 반영됩니다."
echo
docker --version
docker compose version
