#!/usr/bin/env bash
# Возвращает исходный конфиг VLESS gRPC (без TLS) и включает в нём VLESS Encryption.
#
# Новые клиенты Xray (Happ 6.x) не подключаются к VLESS без TLS, если не включено
# VLESS Encryption. Этот скрипт оставляет всё как было (порт, UUID, gRPC),
# меняет только "decryption": "none" на ключ шифрования и печатает новую ссылку.
#
# Запуск на VPS от root:
#   bash enable-vless-encryption.sh
set -euo pipefail

DIR=/usr/local/etc/xray
CONFIG=$DIR/config.json
XRAY=/usr/local/bin/xray

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root (sudo -i)." >&2
  exit 1
fi

# Самая старая резервная копия — исходный рабочий конфиг до install-vless-reality.sh.
ORIGINAL="$(ls -1tr "$DIR"/config.json.bak.* 2>/dev/null | head -n 1 || true)"
if [[ -z "$ORIGINAL" ]]; then
  echo "Не найдена резервная копия $DIR/config.json.bak.*; беру текущий config.json."
  ORIGINAL=$CONFIG
fi
echo "Исходный конфиг: $ORIGINAL"
cp "$CONFIG" "$CONFIG.before-encryption.$(date +%Y%m%d-%H%M%S)"

ENC_OUT="$($XRAY vlessenc)"
DECRYPTION="$(echo "$ENC_OUT" | grep -m1 '"decryption"' | cut -d'"' -f4)"
ENCRYPTION="$(echo "$ENC_OUT" | grep -m1 '"encryption"' | cut -d'"' -f4)"
if [[ -z "$DECRYPTION" || -z "$ENCRYPTION" ]]; then
  echo "Не удалось разобрать вывод 'xray vlessenc':" >&2
  echo "$ENC_OUT" >&2
  exit 1
fi

SERVER_IP="$(curl -4 -fsS https://api.ipify.org || hostname -I | awk '{print $1}')"

python3 - "$ORIGINAL" "$CONFIG" "$DECRYPTION" "$ENCRYPTION" "$SERVER_IP" <<'PY'
import json, sys, urllib.parse

src, dst, decryption, encryption, ip = sys.argv[1:]
with open(src) as f:
    cfg = json.load(f)

links = []
for inbound in cfg.get("inbounds", []):
    if inbound.get("protocol") != "vless":
        continue
    settings = inbound.setdefault("settings", {})
    settings["decryption"] = decryption
    stream = inbound.get("streamSettings", {})
    network = stream.get("network", "tcp")
    for client in settings.get("clients", []):
        client.pop("flow", None)  # flow несовместим с gRPC
        params = {"encryption": encryption, "type": network}
        if network == "grpc":
            params["serviceName"] = stream.get("grpcSettings", {}).get("serviceName", "")
        params["packetEncoding"] = "xudp"
        name = client.get("email") or inbound.get("tag") or "VLESS"
        query = urllib.parse.urlencode(params, safe="")
        links.append(f"vless://{client['id']}@{ip}:{inbound['port']}?{query}#{urllib.parse.quote(name)}")

if not links:
    sys.exit("В конфиге нет VLESS-инбаундов.")

with open(dst, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
with open("/root/vless-encryption-link.txt", "w") as f:
    f.write("\n".join(links) + "\n")
PY

$XRAY run -test -config "$CONFIG"
systemctl restart xray

echo
echo "Готово. Xray: $(systemctl is-active xray)"
echo "Новая ссылка сохранена в /root/vless-encryption-link.txt"
echo "Скопируйте её в буфер на компьютере командой из README (не выделяйте мышкой)."
