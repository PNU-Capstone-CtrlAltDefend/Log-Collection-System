# 4) 로컬 mitmproxy 설치(또는 재설치)
command -v mitmdump && mitmdump —version || true
sudo apt purge -y mitmproxy || true
sudo apt autoremove -y
sudo apt update
sudo apt install -y mitmproxy

mitmdump -q —listen-port 8081 & sleep 2; pkill -f mitmdump
ls -al ~/.mitmproxy   # mitmproxy-ca-cert.pem 보이면 OK

umask 002
mitmdump -p 8081 \
  -s ./email_script.py \
  -s ./http_script.py \
  —set confdir="$HOME/.mitmproxy" \
  —set termlog_verbosity=info \
  —set flow_detail=2
