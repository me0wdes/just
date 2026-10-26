#!/usr/bin/env bash
# Installs the Just sync server on Debian or Ubuntu and prints a connection
# string for the app.
#
#   curl -fsSL https://raw.githubusercontent.com/me0wdes/just/main/server/install.sh | sudo bash
#   sudo JUST_DOMAIN=tasks.example.com bash install.sh     # with your own domain
#   sudo JUST_MODE=direct bash install.sh                  # switch a domain server to direct
#
# Direct (the default without a domain): Just answers HTTPS itself on the IP,
# on 443 or the first free port after it, with its own certificate. Its
# fingerprint goes into the connection string and the app trusts only it, so
# busy ports, a missing domain or a blocked sslip.io do not matter.
# Domain: nginx, Apache or Caddy in front with a Let's Encrypt certificate.
# Re-running updates the code and keeps the data, the key and the mode.
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
apt-get install -y -qq git curl ca-certificates gnupg openssl sqlite3 qrencode debian-keyring debian-archive-keyring apt-transport-https >/dev/null

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
chmod +x "$APP/just-sync.sh" && ln -sf "$APP/just-sync.sh" /usr/local/bin/just-sync
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

setenv() { sed -i "/^$1=/d" "$ENV_FILE" && echo "$1=$2" >> "$ENV_FILE"; }
mode=${JUST_MODE:-$(sed -n 's/^JUST_MODE=//p' "$ENV_FILE")}
# Servers set up before the direct mode keep their domain on updates.
if [[ -z $mode ]]; then
  [[ -n ${JUST_DOMAIN:-}$(sed -n 's/^JUST_DOMAIN=//p' "$ENV_FILE") ]] && mode=domain || mode=direct
fi
[[ $mode == direct || $mode == domain ]] || { echo "JUST_MODE: direct или domain"; exit 1; }
setenv JUST_MODE "$mode"
if [[ $mode == direct ]]; then
  ip=$(curl -fsS4 https://api.ipify.org)
  ours() { ss -ltnpH "( sport = :$1 )" 2>/dev/null | grep -q '"node"'; }
  free() { ! ss -ltnH "( sport = :$1 )" 2>/dev/null | grep -q .; }
  pub=${JUST_PORT:-$(sed -n 's/^JUST_PORT=//p' "$ENV_FILE")}
  if [[ -z $pub ]] || ! { free "$pub" || ours "$pub"; }; then
    pub=""
    for p in 443 8443 2053 2083 2087 2096 9443 10443; do free "$p" && { pub=$p; break; }; done
  fi
  [[ -n $pub ]] || { echo "Все порты 443, 8443, 2053, 2083, 2087, 2096, 9443, 10443 заняты. Укажите свободный: sudo JUST_PORT=12345 bash install.sh"; exit 1; }
  tls=$DATA/tls
  mkdir -p "$tls"
  # A certificate for this IP, made once; a new IP gets a new one.
  if [[ ! -f $tls/cert.pem ]] || ! openssl x509 -in "$tls/cert.pem" -noout -checkip "$ip" | grep -q 'does match'; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
      -subj '/CN=Just sync' -addext "subjectAltName=IP:$ip" \
      -keyout "$tls/key.pem" -out "$tls/cert.pem" 2>/dev/null
  fi
  chown -R just-sync:just-sync "$tls" && chmod 600 "$tls/key.pem"
  setenv JUST_PORT "$pub"
  setenv JUST_ENDPOINT "https://$ip:$pub/sync"
  setenv JUST_PIN "$(openssl x509 -in "$tls/cert.pem" -outform der | sha256sum | cut -d' ' -f1)"
  listen="--host 0.0.0.0 --port $pub --tls-cert $tls/cert.pem --tls-key $tls/key.pem"
else
  sed -i '/^JUST_PIN=/d;/^JUST_ENDPOINT=/d' "$ENV_FILE"
  listen="--port $PORT"
fi

cat > /etc/systemd/system/just-sync.service <<EOF
[Unit]
Description=Just sync server
After=network-online.target

[Service]
User=just-sync
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/node $APP/src/index.mjs --data $DATA $listen
# Lets the direct mode answer on 443 without running as root.
AmbientCapabilities=CAP_NET_BIND_SERVICE
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
ExecStart=/bin/bash $APP/just-sync.sh backup
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
if [[ $mode == direct ]]; then
  echo "Just отвечает сам на порту $pub, со своим сертификатом."
  if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then ufw allow "$pub/tcp" >/dev/null; fi
else
  # The domain is remembered, so nightly updates keep the same address.
  domain=${JUST_DOMAIN:-$(sed -n 's/^JUST_DOMAIN=//p' "$ENV_FILE")}
  if [[ -z $domain ]]; then
    ip=$(curl -fsS4 https://api.ipify.org)
    domain="${ip//./-}.sslip.io"
  fi
  sed -i '/^JUST_DOMAIN=/d' "$ENV_FILE" && echo "JUST_DOMAIN=$domain" >> "$ENV_FILE"
  # Whoever already answers on 80/443 keeps them: Just joins nginx or Apache
  # as one more site with its own certificate, and brings Caddy only to an
  # empty server.
  web=$(ss -ltnpH '( sport = :80 or sport = :443 )' 2>/dev/null | grep -oE '"(nginx|apache2|httpd|caddy)"' | head -1 | tr -d '"' || true)
  [[ -z $web ]] && ss -ltnH '( sport = :80 or sport = :443 )' 2>/dev/null | grep -q . && web=other
  certbot_for() {
    command -v certbot >/dev/null || apt-get install -y -qq certbot "python3-certbot-$1" >/dev/null
    certbot --"$1" -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect --keep-until-expiring >/dev/null
  }
  case $web in
    nginx)
      echo "На сервере уже работает nginx, добавляю Just к нему отдельным сайтом."
      cat > /etc/nginx/conf.d/just-sync.conf <<EOF
  server {
    listen 80;
    server_name $domain;
    client_max_body_size 10m;
    location / {
      proxy_pass http://127.0.0.1:$PORT;
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
    }
  }
EOF
      nginx -t >/dev/null 2>&1 || { echo "nginx не принял настройку. Пришлите вывод: sudo nginx -t"; exit 1; }
      systemctl reload nginx
      certbot_for nginx ;;
    apache2|httpd)
      echo "На сервере уже работает Apache, добавляю Just к нему отдельным сайтом."
      a2enmod -q proxy proxy_http headers >/dev/null
      cat > /etc/apache2/sites-available/just-sync.conf <<EOF
  <VirtualHost *:80>
    ServerName $domain
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/
  </VirtualHost>
EOF
      a2ensite -q just-sync >/dev/null && systemctl reload apache2
      certbot_for apache ;;
    other)
      echo "Порты 80 и 443 заняты программой, которую установщик не знает:"
      ss -ltnp '( sport = :80 or sport = :443 )' | tail -n +2
      echo "Освободите их или запустите установку с JUST_DOMAIN на сервере без сайтов."
      exit 1 ;;
    *)
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
      systemctl reload caddy 2>/dev/null || systemctl restart caddy ;;
  esac
  if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    ufw allow 80/tcp >/dev/null && ufw allow 443/tcp >/dev/null
  fi

fi

say "6/6 Проверка"
if [[ $mode == direct ]]; then
  endpoint="https://$ip:$pub/sync"
  check=(-k)
else
  endpoint="https://$domain/sync"
  check=()
fi
for _ in $(seq 1 30); do
  code=$(curl -s "${check[@]}" -o /dev/null -w '%{http_code}' -X POST "$endpoint" || true)
  [[ $code == 401 || $code == 400 ]] && break
  sleep 2
done
if [[ ${code:-} == 401 || ${code:-} == 400 ]]; then
  echo "Сервер отвечает по $endpoint"
elif [[ $mode == direct ]]; then
  echo "Порт $pub пока не отвечает. Если у хостинга есть брандмауэр в панели управления, откройте в нём TCP-порт $pub."
else
  echo "HTTPS пока не отвечает. Проверьте, что порты 80 и 443 открыты, и запустите скрипт ещё раз."
fi

# The key never goes to the journal of the nightly update.
[[ -n ${JUST_AUTO:-} ]] && { echo "Обновлено до $(cat "$APP/.revision")"; exit 0; }
say "Готово. Ваша строка подключения:"
bash "$APP/just-sync.sh" owner
echo "Показать снова: sudo just-sync owner. Добавить ещё человека: sudo just-sync add <имя>"
