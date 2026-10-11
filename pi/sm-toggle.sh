#!/bin/bash
# Переключает: экран Windows <-> рабочий стол Pi. Код 1 - стрим не запущен.
D=$(dirname "$(readlink -f "$0")"); . "$D/sm-common.sh"
has_window || { echo "стрим не запущен" >&2; exit 1; }
if is_minimized; then
  "$D/sm-panel.sh" stop
  wlrctl toplevel focus "app_id:$APP"
else
  wlrctl toplevel minimize "app_id:$APP"
  "$D/sm-panel.sh" start
fi
exit 0
