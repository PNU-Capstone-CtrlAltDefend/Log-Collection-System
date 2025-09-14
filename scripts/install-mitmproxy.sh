docker cp log-collect-proxy-agent:/app/email_script.py ./email_script.py
docker cp log-collect-proxy-agent:/app/http_script.py  ./http_script.py
docker cp log-collect-proxy-agent:/app/requirements.txt ./requirements.txt

docker compose stop proxy-agent || docker stop log-collect-proxy-agent
docker compose rm -f proxy-agent || true
pkill -f 'mitmproxy|mitmdump' 2>/dev/null || true
sudo ss -ltnp | grep ':8081' || echo "8081 free"

sudo rm -f /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates
rm -rf ~/Log-Collection-System/mitmproxy 2>/dev/null || true
rm -rf ~/.mitmproxy 2>/dev/null || true

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
