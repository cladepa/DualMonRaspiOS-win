#!/bin/bash
# Полная остановка: стрим, сеанс в Apollo (виртуальный монитор исчезает), панель Pi возвращается.
D=$(dirname "$(readlink -f "$0")"); . "$D/sm-common.sh"
rm -f "$WANTED"                      # чтобы автовосстановление не включило стрим обратно
pkill -f 'sm-start.sh --run'
pkill moonlight-qt
sleep 1
apollo_quit "$(cat "$HOSTFILE" 2>/dev/null)"
"$D/sm-panel.sh" start
exit 0
