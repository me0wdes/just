#!/usr/bin/env bash
# People on one Just sync server. Everyone gets an own key and an own database,
# so nobody sees anyone else's tasks.
#
#   sudo just-sync add mama       new person, or a new key for mama (her tasks stay)
#   sudo just-sync remove mama    closes access, her tasks stay on disk
#   sudo just-sync list
#   sudo just-sync owner          the server owner's connection string again
set -euo pipefail
shopt -s nullglob

APP=/opt/just-sync
DATA=/var/lib/just-sync
ENV_FILE=/etc/just-sync.env

usage() { sed -n '5,8p' "$0" | sed 's/^#   //'; exit 1; }
[[ $EUID -eq 0 || ${1:-} == backup ]] || { echo "Запустите через sudo."; exit 1; }

connection() {
  local domain conn
  domain=$(sed -n 's/^JUST_DOMAIN=//p' "$ENV_FILE")
  conn="just1:$(printf '{"u":"https://%s/sync","k":"%s"}' "$domain" "$1" | base64 -w0 | tr '+/' '-_' | tr -d '=')"
  echo
  echo "$conn"
  echo
  qrencode -t ansiutf8 "$conn" || true
  echo "В Just: Настройки → Хранение данных → Свой сервер. Строка содержит ключ доступа: передайте её лично, как пароль."
}

name=${2:-}
if [[ ${1:-} == add || ${1:-} == remove ]]; then
  [[ $name =~ ^[a-z0-9_-]{1,32}$ ]] || { echo "Имя: латиница в нижнем регистре, цифры, - и _, до 32 символов."; exit 1; }
fi

case ${1:-} in
  add)
    dir=$DATA/users/$name
    [[ -f $dir/key.sha256 ]] && echo "У $name уже есть доступ: выдаю новый ключ, старый перестанет работать. Задачи сохранятся."
    mkdir -p "$dir"
    token=$(node "$APP/src/index.mjs" --generate-token)
    # Only the hash is stored: a lost string is replaced by running add again.
    printf %s "$token" | sha256sum | cut -d' ' -f1 > "$dir/key.sha256"
    chown -R just-sync:just-sync "$dir" && chmod 700 "$dir"
    systemctl restart just-sync
    echo "Строка подключения для $name:"
    connection "$token" ;;
  remove)
    rm -f "$DATA/users/$name/key.sha256"
    systemctl restart just-sync
    echo "Доступ для $name закрыт. Задачи остались в $DATA/users/$name, удалить их: sudo rm -r $DATA/users/$name" ;;
  list)
    echo "owner (владелец сервера)"
    for key in "$DATA"/users/*/key.sha256; do basename "$(dirname "$key")"; done ;;
  owner)
    connection "$(sed -n 's/^DAY_SYNC_TOKEN=//p' "$ENV_FILE")" ;;
  backup)
    # Runs daily from just-sync-backup.timer; keeps 14 days.
    day=$(date +%F)
    sqlite3 "$DATA/sync.sqlite" ".backup $DATA/backups/sync-$day.sqlite"
    for db in "$DATA"/users/*/sync.sqlite; do
      sqlite3 "$db" ".backup $DATA/backups/user-$(basename "$(dirname "$db")")-$day.sqlite"
    done
    find "$DATA/backups" -name '*.sqlite' -mtime +14 -delete ;;
  *) usage ;;
esac
