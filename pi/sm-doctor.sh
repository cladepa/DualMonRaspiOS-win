#!/bin/bash
# Диагностика стороны Pi: «всё установлено, но ничего не работает».
D=$(dirname "$(readlink -f "$0")"); . "$D/sm-common.sh"
FAILS=0
ok()   { echo "[ OK ] $*"; }
bad()  { echo "[FAIL] $*"; FAILS=$((FAILS+1)); }
warn() { echo "[WARN] $*"; }

echo "== Программы =="
if command -v moonlight-qt >/dev/null; then
  ok "moonlight-qt: $(QT_QPA_PLATFORM=offscreen moonlight-qt --version 2>/dev/null | head -1)"
else bad "moonlight-qt не установлен -> запусти install-pi.sh"; fi
command -v wlrctl >/dev/null && ok "wlrctl установлен" || bad "wlrctl не установлен -> sudo apt install wlrctl"
command -v flock  >/dev/null && ok "flock есть" || bad "flock нет (пакет util-linux)"

echo "== Рабочий стол =="
pgrep -x labwc >/dev/null && ok "labwc запущен" || bad "labwc не запущен (скрипты рассчитаны на labwc/Wayland)"
[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && ok "сокет Wayland: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" || bad "нет сокета Wayland $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY (проверь: ls $XDG_RUNTIME_DIR | grep wayland)"
pgrep -x xfce4-panel >/dev/null && ok "xfce4-panel виден" || warn "xfce4-panel не запущен (нормально, если стрим идёт; иначе: sm-panel.sh start)"
[ -f "$HOME/.cache/sm-panel-env" ] && ok "окружение панели сохранено" || warn "окружение панели не сохранено (запусти sm-panel.sh start при работающей панели)"

echo "== SSH-доступ с Windows =="
if [ -f "$HOME/.ssh/authorized_keys" ] && grep -q 'sm-ssh.sh' "$HOME/.ssh/authorized_keys"; then
  ok "в authorized_keys ключей для sm-ssh.sh: $(grep -c 'sm-ssh.sh' "$HOME/.ssh/authorized_keys")"
else bad "в ~/.ssh/authorized_keys нет ключа для sm-ssh.sh -> запусти install-windows.ps1 на Windows, потом install-pi.sh здесь"; fi
systemctl is-active --quiet ssh && ok "служба ssh работает" || warn "служба ssh не активна (sudo systemctl enable --now ssh)"

echo "== Адреса Windows (порядок проверки) =="
n=0
while read -r h; do
  n=$((n+1))
  ip=$(getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1}')
  if [ -z "$ip" ]; then echo "       $h : имя не разрешается"; continue; fi
  if ping -c1 -W1 "$ip" >/dev/null 2>&1; then P="пинг есть"; else P="пинга нет"; fi
  C=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://$ip:$APOLLO_PORT/serverinfo")
  if [ "$C" = 200 ]; then ok "$h ($ip): $P, Apollo отвечает"; GOOD=$ip
  else warn "$h ($ip): $P, Apollo на порту $APOLLO_PORT не отвечает (код $C)"; fi
done < <(windows_hosts)
[ $n = 0 ] && bad "списки адресов пусты -> sm-hosts.sh add АДРЕС_WINDOWS"
[ -z "$GOOD" ] && bad "ни один адрес Windows не ответил. Проверь: Windows включён? служба ApolloService запущена? адрес сменился? -> sm-hosts.sh add НОВЫЙ_АДРЕС"

if [ -n "$GOOD" ]; then
  echo "== Спаривание и приложение =="
  L=$(QT_QPA_PLATFORM=offscreen timeout 15 moonlight-qt list "$GOOD" 2>&1 | grep -vE 'DRM|HDMI1|SDL |Qt Info|Qt Warning|Found unexpected')
  if echo "$L" | grep -qxF "$APP_NAME"; then ok "приложение '$APP_NAME' найдено в Apollo"
  elif echo "$L" | grep -qi 'fail'; then bad "не удалось получить список приложений (процесс moonlight-qt уже запущен? выполни: pkill moonlight-qt; или нет спаривания: moonlight-qt pair $GOOD)"
  else bad "приложения '$APP_NAME' нет в Apollo. Есть: $(echo "$L" | tr '\n' ',') -> создай его на вкладке Applications"; fi
fi

echo "== Состояние стрима =="
if flock -n 8 8>"$LOCK"; then echo "       блокировка свободна: стрим не запущен"; else echo "       блокировка занята: стрим идёт или запускается"; fi
pgrep -a moonlight-qt >/dev/null && echo "       процесс moonlight-qt: есть" || echo "       процесс moonlight-qt: нет"
has_window && { is_minimized && echo "       окно стрима: свёрнуто" || echo "       окно стрима: на экране"; } || echo "       окна стрима нет"
[ -e "$WANTED" ] && echo "       стрим желаемый: да (после обрыва будет восстановлен; режим: $(cat "$MODEF" 2>/dev/null))" || echo "       стрим желаемый: нет"
echo "== Последние строки лога ($LOG) =="
grep -vE 'DRM|HDMI1|FFmpeg' "$LOG" 2>/dev/null | tail -8

echo
[ $FAILS = 0 ] && echo "Итог: критичных проблем не найдено." || echo "Итог: проблем найдено: $FAILS (см. [FAIL] выше)."
