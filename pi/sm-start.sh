#!/bin/bash
# Запуск второго монитора. Коды выхода (их видит трей Windows):
#   0 - запускается   3 - Windows/Apollo не найдены по адресам из списка
#   4 - уже запущено (если окно было свёрнуто - вернули его на экран)
# После обрыва связи скрипт сам восстанавливает стрим и прежний режим
# (экран Windows или рабочий стол Pi) в течение RECONNECT_MAX_SEC секунд.
D=$(dirname "$(readlink -f "$0")"); . "$D/sm-common.sh"

if [ "$1" != "--run" ]; then
  # --- передний план: быстрые проверки, потом фоновый процесс ---
  exec 9>"$LOCK"
  if ! flock -n 9; then
    is_minimized && "$D/sm-toggle.sh"
    exit 4
  fi
  write_pi_auto
  HOST=$(find_windows)
  if [ -z "$HOST" ]; then
    echo "$(date +%T) [sm] Windows не найден ни по одному адресу: $(windows_hosts | tr '\n' ' ')" > "$LOG"
    exit 3
  fi
  echo "$HOST" > "$HOSTFILE"
  setsid nohup "$0" --run "$HOST" >/dev/null 2>&1 </dev/null &
  exit 0
fi

# --- фоновый процесс (держит блокировку, унаследованную в fd 9) ---
HOST=$2
MPID=; REASON=
cleanup() { rm -f "$WANTED"; "$D/sm-panel.sh" start; }
trap cleanup EXIT
trap 'exit 1' TERM INT HUP

[ -f "$LOG" ] && cp -f "$LOG" "$LOG.prev"
: > "$LOG"

# Одна попытка подключения. 0 - пошёл видеопоток (MPID = процесс Moonlight).
connect() {
  local br n0 i
  case "$1" in 192.168.*|10.*) br=$BITRATE_LAN ;; *) br=$BITRATE_WAN ;; esac
  [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 3000000 ] && : > "$LOG"
  n0=$(wc -l < "$LOG")
  echo "[sm] подключаюсь: host=$1 br=$br" >> "$LOG"
  QT_QPA_PLATFORM=wayland moonlight-qt stream "$1" "$APP_NAME" $RESOLUTION \
    --fps "$FPS" --bitrate "$br" --video-codec "$CODEC" --display-mode fullscreen --quit-after \
    >> "$LOG" 2>&1 9>&- &
  MPID=$!
  for i in $(seq 1 60); do
    kill -0 "$MPID" 2>/dev/null || return 1
    tail -n +$((n0+1)) "$LOG" | grep -q 'Received first video packet' && return 0
    sleep 0.5
  done
  kill "$MPID" 2>/dev/null; wait "$MPID" 2>/dev/null
  return 1
}

# Пока стрим жив: панель Pi видна, только когда окно свёрнуто; запоминает режим;
# следит за обрывом. Итог в REASON: user (закрыл сам) | stop (команда stop) | drop (обрыв).
watch() {
  local state="" n rc
  n=$(wc -l < "$LOG")
  sleep 2
  [ "$1" = minimized ] && wlrctl toplevel minimize "app_id:$APP" >/dev/null 2>&1
  while kill -0 "$MPID" 2>/dev/null; do
    if has_window; then            # пока окна нет (закрылось при обрыве), режим не трогаем
      if is_minimized; then
        [ "$state" != shown ] && { "$D/sm-panel.sh" start; state=shown; echo minimized > "$MODEF"; }
      else
        [ "$state" != hidden ] && { "$D/sm-panel.sh" stop; state=hidden; echo window > "$MODEF"; }
      fi
    fi
    if tail -n +$((n+1)) "$LOG" | grep -qE 'Connection terminated|Starting .* failed'; then
      echo "[sm] обрыв соединения, закрываю Moonlight" >> "$LOG"
      kill "$MPID" 2>/dev/null; wait "$MPID" 2>/dev/null
      REASON=drop; return
    fi
    sleep 0.7
  done
  wait "$MPID" 2>/dev/null; rc=$?
  echo "[sm] Moonlight завершился, код=$rc" >> "$LOG"
  if [ ! -e "$WANTED" ]; then REASON=stop
  elif tail -n +$((n+1)) "$LOG" | grep -qE 'Connection terminated|Starting .* failed'; then REASON=drop
  elif [ "$rc" -ge 128 ]; then REASON=drop     # Moonlight упал по сигналу
  else REASON=user; fi
}

pkill moonlight-qt; sleep 1
apollo_quit "$HOST"; sleep 2        # чистим возможный «зависший» сеанс - только при первом запуске
touch "$WANTED"; echo window > "$MODEF"

FAILS=0; DEADLINE=0; RESTORE=window
while [ -e "$WANTED" ]; do
  H=$(find_windows)
  OKC=0
  if [ -n "$H" ]; then HOST=$H; echo "$HOST" > "$HOSTFILE"; connect "$HOST" && OKC=1; fi
  if [ $OKC = 1 ]; then
    FAILS=0
    [ "$DEADLINE" != 0 ] && echo "[sm] связь восстановлена, режим: $RESTORE" >> "$LOG"
    DEADLINE=0
    watch "$RESTORE"
    [ "$REASON" != drop ] && break
    RESTORE=$(cat "$MODEF" 2>/dev/null || echo window)
    DEADLINE=$(( $(date +%s) + RECONNECT_MAX_SEC ))
    echo "[sm] обрыв связи: пробую восстановить в течение ${RECONNECT_MAX_SEC} с (режим: $RESTORE)" >> "$LOG"
  else
    FAILS=$((FAILS+1))
    if [ "$DEADLINE" = 0 ]; then
      if [ $FAILS -ge 2 ]; then echo "[sm] не удалось подключиться за 2 попытки" >> "$LOG"; break; fi
      apollo_quit "$HOST"
    elif [ "$(date +%s)" -ge "$DEADLINE" ]; then
      echo "[sm] время на восстановление вышло" >> "$LOG"; break
    fi
  fi
  "$D/sm-panel.sh" start            # пока потока нет, рабочий стол Pi доступен
  sleep $(( FAILS < 5 ? 3 : 8 ))
done
apollo_quit "$HOST"
exit 0
