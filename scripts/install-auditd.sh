sudo apt-get update
sudo apt-get install -y auditd audispd-plugins

# 기동 및 부팅 시 자동 시작
sudo systemctl enable auditd
sudo systemctl start auditd

# 상태 확인
sudo systemctl status auditd --no-pager
