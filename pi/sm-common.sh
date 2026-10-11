#!/bin/bash
# Общие функции и настройки. Подключается через: . "$D/sm-common.sh"
# D - каталог скрипта с разрешёнными симлинками (readlink -f).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

SM_ROOT=$(dirname "$D")                 # корень папки Second_monitor
HOSTS_DIR="$SM_ROOT/hosts"
APP=com.moonlight_stream.Moonlight      # app_id окна Moonlight в labwc
LOG=/tmp/sm-start.log
LOCK=/tmp/sm-start.lock
HOSTFILE="$HOME/.cache/sm-host"         # последний удачный адрес Windows
WANTED=/tmp/sm-wanted                   # есть файл = пользователь хочет, чтобы стрим работал
MODEF=/tmp/sm-mode                      # window = экран Windows на Pi, minimized = рабочий стол Pi

# значения по умолчанию, их переопределяет settings.conf
APP_NAME="Second Monitor"; RESOLUTION="--1080"; FPS=60
BITRATE_LAN=12000; BITRATE_WAN=6000; CODEC="H.264"; APOLLO_PORT=47989; RECONNECT_MAX_SEC=600
[ -f "$SM_ROOT/settings.conf" ] && . "$SM_ROOT/settings.conf"

mkdir -p "$HOME/.cache" "$HOSTS_DIR" 2>/dev/null

# Читает файл со списком адресов: убирает CRLF, BOM, комментарии, пустые строки.
read_list() {
  [ -f "$1" ] || return 0
  sed -e '1s/^\xEF\xBB\xBF//' -e 's/\r$//' -e 's/#.*$//' "$1" | awk '{$1=$1; if ($0 != "") print $0}'
}

# Адреса Windows: сначала свежие (auto), потом ручные; без повторов.
windows_hosts() {
  { read_list "$HOSTS_DIR/windows.auto.txt"; read_list "$HOSTS_DIR/windows.manual.txt"; } | awk '!seen[$0]++'
}

# Пишет адреса этой Pi в hosts/pi.auto.txt (читает Windows). Файл не трогает, если ничего не изменилось
# (чтобы Syncthing не гонял его зря).
write_pi_auto() {
  local tmp="$HOSTS_DIR/.pi.auto.tmp.$$"
  {
    echo "# Пишется автоматически скриптами Pi. Руками не правь."
    echo "# Свои адреса добавляй в pi.manual.txt"
    ip -4 -o addr show scope global 2>/dev/null | awk '$2 !~ /^(lo|lxcbr|docker|veth|br-)/ {split($4,a,"/"); print a[1]}'
    echo "$(hostname).local"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  if [ -f "$HOSTS_DIR/pi.auto.txt" ] && cmp -s "$tmp" "$HOSTS_DIR/pi.auto.txt"; then rm -f "$tmp"; else mv -f "$tmp" "$HOSTS_DIR/pi.auto.txt"; fi
}

# Первый ответивший адрес Windows (по порту Apollo). Печатает IP.
find_windows() {
  local h ip
  while read -r h; do
    ip=$(getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1}')
    [ -z "$ip" ] && continue
    if [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://$ip:$APOLLO_PORT/serverinfo")" = "200" ]; then
      echo "$ip"; return 0
    fi
  done < <(windows_hosts)
  return 1
}

# Тихо просит Apollo закрыть приложение (чистит «зависший» сеанс).
apollo_quit() {
  [ -n "$1" ] && QT_QPA_PLATFORM=offscreen timeout 10 moonlight-qt quit "$1" >/dev/null 2>&1 9>&-
}

is_minimized() { wlrctl toplevel find "app_id:$APP" state:minimized >/dev/null 2>&1; }
has_window()   { wlrctl toplevel find "app_id:$APP" >/dev/null 2>&1; }
