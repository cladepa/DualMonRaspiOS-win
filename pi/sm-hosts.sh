#!/bin/bash
# Список адресов Windows, которые пробует Pi.
#   sm-hosts.sh            показать списки
#   sm-hosts.sh add АДРЕС  добавить в ручной список
#   sm-hosts.sh edit       открыть ручной список в редакторе
#   sm-hosts.sh refresh    обновить hosts/pi.auto.txt (адреса этой Pi); вызывается таймером
D=$(dirname "$(readlink -f "$0")"); . "$D/sm-common.sh"
F="$HOSTS_DIR/windows.manual.txt"
case "$1" in
  add)  [ -n "$2" ] || { echo "укажи адрес: sm-hosts.sh add 192.168.1.50"; exit 2; }
        read_list "$F" | grep -qxF -- "$2" || echo "$2" >> "$F"
        echo "Добавлено. Теперь список:" ;;
  edit) ${EDITOR:-nano} "$F"; exit 0 ;;
  refresh) write_pi_auto; exit 0 ;;
esac
echo "--- windows.auto.txt (пишет Windows сам) ---";  read_list "$HOSTS_DIR/windows.auto.txt"
echo "--- windows.manual.txt (ручной) ---";           read_list "$F"
echo "--- порядок проверки ---";                      windows_hosts
