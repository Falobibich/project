# VPN на VPS: VLESS + REALITY + gRPC

## Почему сломался VLESS gRPC

Happ 6.0.0 обновил ядро Xray. Новые версии Xray отказываются запускать VLESS
с `security: "none"` (без TLS/шифрования), если сервер — публичный IP:

```
failed to build outbound config with tag proxy - vless without TLS or other
encryption is prohibited unless the server address is a private IP or domain
```

Сервер тут ни при чём — ошибка на стороне клиента. Исправление: включить на
сервере REALITY (или TLS) для этого подключения. REALITY не требует ни домена,
ни сертификата. Hysteria2 это не касается — он работает как раньше.

## Установка

На VPS (Debian/Ubuntu) от root:

```bash
curl -fsSLO https://raw.githubusercontent.com/falobibich/project/main/install-vless-reality.sh
bash install-vless-reality.sh
```

(Если скрипт ещё не в `main`, замените `main` на имя ветки.)

Скрипт:

1. Ставит/обновляет Xray официальным установщиком.
2. Генерирует UUID, ключи REALITY и shortId.
3. Сохраняет старый `/usr/local/etc/xray/config.json` в `config.json.bak.<дата>`
   и пишет новый конфиг (VLESS + REALITY + gRPC).
4. Перезапускает Xray и печатает ссылку `vless://...` для Happ.

Параметры через переменные окружения:

| Переменная     | По умолчанию        | Что это                                  |
|----------------|---------------------|------------------------------------------|
| `PORT`         | `443`               | TCP-порт сервера                         |
| `SNI`          | `www.microsoft.com` | Сайт, под который маскируется REALITY    |
| `SERVICE_NAME` | `grpc`              | Имя gRPC-сервиса                         |

Пример: `PORT=8443 bash install-vless-reality.sh`

## В Happ

Скопируйте выведенную ссылку → в Happ «+» → «Импорт из буфера». Старый
VLESS-профиль удалите.

## Если стоит панель (3x-ui, Marzban и т.п.)

Скрипт не запускайте — он перезапишет конфиг Xray. Вместо этого в панели
откройте VLESS-инбаунд и смените Security с `none` на `reality`
(нажмите «Get New Cert»/сгенерировать ключи), сохраните и заново выдайте
ссылку клиенту.

## Вариант 2: как было (VLESS gRPC без TLS) + VLESS Encryption

Если REALITY не проходит у вашего провайдера, а старый VLESS gRPC без TLS работал,
`enable-vless-encryption.sh` возвращает исходный конфиг (из самой старой
резервной копии) и включает в нём VLESS Encryption — именно его требует Happ 6.x.

Из PowerShell на компьютере (не на сервере):

```powershell
ssh root@87.199.209.117 "curl -fsSL https://raw.githubusercontent.com/falobibich/project/claude/github-quota-100-a0fwds/enable-vless-encryption.sh -o /root/enable-vless-encryption.sh && bash /root/enable-vless-encryption.sh"
ssh root@87.199.209.117 "cat /root/vless-encryption-link.txt" | Set-Clipboard
```

Вторая команда кладёт ссылку сразу в буфер обмена — дальше Happ → «+» →
«Импорт из буфера».
