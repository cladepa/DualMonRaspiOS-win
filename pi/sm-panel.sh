#!/bin/bash
# Прячет/возвращает xfce4-panel (именно она «просвечивает» поверх стрима).
# Использование: sm-panel.sh start|stop. Безопасно вызывать повторно.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
ENVF=$HOME/.cache/sm-panel-env
P=$(pgrep -xo xfce4-panel)
if [ -n "$P" ]; then
  tr '\0' '\n' < /proc/$P/environ | grep -E '^(DISPLAY|DBUS_SESSION_BUS_ADDRESS|XAUTHORITY)=' \
    | sed "s/^\([^=]*\)=\(.*\)$/export \1='\2'/" > "$ENVF"
fi
[ -f "$ENVF" ] && . "$ENVF"
export DISPLAY=${DISPLAY:-:0}
case "$1" in
  stop)
    pkill -f 'lwrespawn xfce4-panel'; pkill -x xfce4-panel ;;
  start)
    if ! pgrep -x xfce4-panel >/dev/null; then
      setsid nohup lwrespawn xfce4-panel >/dev/null 2>&1 9>&- &
    fi ;;
  *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
exit 0
