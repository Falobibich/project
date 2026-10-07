#!/usr/bin/env bash
# Устанавливает/обновляет Xray и настраивает VLESS + REALITY + gRPC.
#
# Новые версии Xray (в т.ч. в Happ 6.x) запрещают VLESS с security "none"
# на публичном адресе. REALITY даёт шифрование без своего домена и сертификата.
#
# Запуск на VPS от root:
#   bash install-vless-reality.sh
# Параметры (необязательно):
#   PORT=443 SNI=www.microsoft.com SERVICE_NAME=grpc bash install-vless-reality.sh
set -euo pipefail

PORT="${PORT:-443}"
SNI="${SNI:-www.microsoft.com}"
SERVICE_NAME="${SERVICE_NAME:-grpc}"
CONFIG=/usr/local/etc/xray/config.json
XRAY=/usr/local/bin/xray

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root (sudo -i)." >&2
  exit 1
fi

if ss -ltnpH "sport = :$PORT" | grep -qv xray; then
  echo "Порт TCP $PORT занят другим процессом:" >&2
  ss -ltnp "sport = :$PORT" >&2
  echo "Освободите его или задайте другой: PORT=8443 bash $0" >&2
  exit 1
fi

command -v curl >/dev/null || { apt-get update && apt-get install -y curl; }
command -v openssl >/dev/null || { apt-get update && apt-get install -y openssl; }

# Официальный установщик: ставит последнюю версию Xray и systemd-сервис.
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

UUID="$($XRAY uuid)"
KEYS="$($XRAY x25519)"
PRIVATE_KEY="$(echo "$KEYS" | awk -F': *' '/^Private ?[Kk]ey/ {print $2}')"
# В новых версиях публичный ключ называется "Password", в старых — "Public key".
PUBLIC_KEY="$(echo "$KEYS" | awk -F': *' '/^(Public ?[Kk]ey|Password)/ {print $2; exit}')"
SHORT_ID="$(openssl rand -hex 8)"
SERVER_IP="$(curl -4 -fsS https://api.ipify.org || hostname -I | awk '{print $1}')"

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
  echo "Не удалось разобрать вывод 'xray x25519':" >&2
  echo "$KEYS" >&2
  exit 1
fi

if [[ -f $CONFIG ]]; then
  cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
fi

cat >"$CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-reality-grpc",
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "$SERVICE_NAME" },
        "security": "reality",
        "realitySettings": {
          "target": "$SNI:443",
          "serverNames": [ "$SNI" ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [ "$SHORT_ID" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ]
}
EOF

$XRAY run -test -config "$CONFIG"
systemctl enable xray >/dev/null 2>&1
systemctl restart xray

if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow "$PORT"/tcp
fi

LINK="vless://$UUID@$SERVER_IP:$PORT?encryption=none&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=grpc&serviceName=$SERVICE_NAME&mode=gun#VLESS-Reality-gRPC"

echo
echo "Готово. Xray: $(systemctl is-active xray)"
echo "Ссылка для Happ (скопируйте и импортируйте из буфера):"
echo
echo "$LINK"
echo
echo "$LINK" >/root/vless-reality-link.txt
echo "Ссылка сохранена в /root/vless-reality-link.txt"
