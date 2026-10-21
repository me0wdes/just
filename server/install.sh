#!/usr/bin/env bash
# Installs the Just sync server on Debian or Ubuntu and prints a connection
# string for the app.
#
#   curl -fsSL https://raw.githubusercontent.com/me0wdes/just/main/server/install.sh | sudo bash
#   sudo JUST_DOMAIN=tasks.example.com bash install.sh     # with your own domain
#
# Without JUST_DOMAIN the server gets <ip>.sslip.io, a free name that points at
# this machine, so Caddy can still issue a real HTTPS certificate.
# Re-running updates the code and keeps the data, the key and the domain.
# A nightly timer re-runs it (JUST_AUTO=1) whenever the repository has a new version.
set -euo pipefail

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "Запустите через sudo."; exit 1; }
command -v apt-get >/dev/null || { echo "Нужен Debian или Ubuntu."; exit 1; }

REPO=${JUST_REPO:-https://github.com/me0wdes/just.git}
APP=/opt/just-sync
DATA=/var/lib/just-sync
ENV_FILE=/etc/just-sync.env
PORT=18766

if [[ -n ${JUST_AUTO:-} ]]; then
  rev=$(git ls-remote "$REPO" HEAD | cut -f1)
  [[ -n $rev && $rev == "$(cat "$APP/.revision" 2>/dev/null)" ]] && { echo "Уже последняя версия"; exit 0; }
fi

say "1/6 Пакеты"
apt-get update -qq
apt-get install -y -qq git curl ca-certificates gnupg sqlite3 qrencode debian-keyring debian-archive-keyring apt-transport-https >/dev/null

say "2/6 Node.js 24"
if ! node -v 2>/dev/null | grep -qE '^v(2[4-9]|[3-9][0-9])\.'; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi
node -v

say "3/6 Сервер Just"
src=$(mktemp -d)
git clone -q --depth 1 "$REPO" "$src"
rm -rf "$APP"
cp -r "$src/server" "$APP"
git -C "$src" rev-parse HEAD > "$APP/.revision"
rm -rf "$src"
(cd "$APP" && npm ci --omit=dev --silent)
id -u just-sync >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin just-sync
mkdir -p "$DATA/backups"
chown -R just-sync:just-sync "$DATA"
chmod 700 "$DATA"
# The key is created once and kept on updates.
if [[ ! -f $ENV_FILE ]]; then
  umask 077
  echo "DAY_SYNC_TOKEN=$(node "$APP/src/index.mjs" --generate-token)" > "$ENV_FILE"
fi
token=$(sed -n 's/^DAY_SYNC_TOKEN=//p' "$ENV_FILE")

cat > /etc/systemd/system/just-sync.service <<EOF
[Unit]
Description=Just sync server
After=network-online.target

[Service]
User=just-sync
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/node $APP/src/index.mjs --data $DATA --port $PORT
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$DATA
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

say "4/6 Ежедневная резервная копия (храним 14 дней)"
cat > /etc/systemd/system/just-sync-backup.service <<EOF
[Unit]
Description=Just sync backup

[Service]
Type=oneshot
User=just-sync
ExecStart=/bin/sh -c 'sqlite3 $DATA/sync.sqlite ".backup $DATA/backups/sync-\$(date +%%F).sqlite" && find $DATA/backups -name "sync-*.sqlite" -mtime +14 -delete'
EOF
cat > /etc/systemd/system/just-sync-backup.timer <<EOF
[Unit]
Description=Daily Just sync backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
cat > /etc/systemd/system/just-sync-update.service <<EOF
[Unit]
Description=Just sync update
After=network-online.target

[Service]
Type=oneshot
Environment=JUST_AUTO=1
ExecStart=/bin/bash $APP/install.sh
EOF
cat > /etc/systemd/system/just-sync-update.timer <<EOF
[Unit]
Description=Nightly Just sync update

[Timer]
OnCalendar=*-*-* 04:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now just-sync just-sync-backup.timer just-sync-update.timer >/dev/null
systemctl restart just-sync

say "5/6 HTTPS"
# The domain is remembered, so nightly updates keep the same address.
domain=${JUST_DOMAIN:-$(sed -n 's/^JUST_DOMAIN=//p' "$ENV_FILE")}
if [[ -z $domain ]]; then
  ip=$(curl -fsS4 https://api.ipify.org)
  domain="${ip//./-}.sslip.io"
fi
sed -i '/^JUST_DOMAIN=/d' "$ENV_FILE" && echo "JUST_DOMAIN=$domain" >> "$ENV_FILE"
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy >/dev/null
fi
cat > /etc/caddy/just-sync.caddy <<EOF
$domain {
  reverse_proxy 127.0.0.1:$PORT
}
EOF
# Keep an existing Caddy setup; only add our site to it.
grep -q 'import just-sync.caddy' /etc/caddy/Caddyfile 2>/dev/null || echo 'import just-sync.caddy' >> /etc/caddy/Caddyfile
systemctl reload caddy 2>/dev/null || systemctl restart caddy
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
  ufw allow 80/tcp >/dev/null && ufw allow 443/tcp >/dev/null
fi

say "6/6 Проверка"
endpoint="https://$domain/sync"
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$endpoint" || true)
  [[ $code == 401 || $code == 400 ]] && break
  sleep 2
done
[[ ${code:-} == 401 || ${code:-} == 400 ]] && echo "Сервер отвечает по $endpoint" \
  || echo "HTTPS пока не отвечает. Проверьте, что порты 80 и 443 открыты, и запустите скрипт ещё раз."

# The key never goes to the journal of the nightly update.
[[ -n ${JUST_AUTO:-} ]] && { echo "Обновлено до $(cat "$APP/.revision")"; exit 0; }
conn="just1:$(printf '{"u":"%s","k":"%s"}' "$endpoint" "$token" | base64 -w0 | tr '+/' '-_' | tr -d '=')"
say "Готово. Строка подключения (в Just: Настройки → Хранение данных → Свой сервер):"
echo
echo "$conn"
echo
qrencode -t ansiutf8 "$conn" || true
echo "Строка содержит ключ доступа: храните её как пароль. Снова показать: sudo bash $APP/install.sh"
