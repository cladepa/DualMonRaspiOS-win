#!/bin/bash
# Установка/обновление стороны Raspberry Pi. Можно запускать повторно.
#   bash install-pi.sh
# Делает: ставит moonlight-qt и wlrctl, раскладывает ссылки в ~/bin,
# разрешает ключи из keys/*.pub (только start/stop/toggle/ping),
# создаёт ярлыки, пишет адреса Pi в hosts/pi.auto.txt.
set -u
ROOT=$(dirname "$(readlink -f "$0")")
BIN="$HOME/bin"
say() { echo "== $*"; }

say "Папка скриптов: $ROOT"
[ -d "$ROOT/pi" ] || { echo "Нет папки $ROOT/pi - папка Second_monitor скопирована не полностью?"; exit 1; }

say "Пакеты"
if ! command -v wlrctl >/dev/null; then sudo apt-get install -y wlrctl; fi
if ! command -v moonlight-qt >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/moonlight-game-streaming/moonlight-qt/setup.deb.sh' \
    | distro=raspbian codename=$(lsb_release -cs) sudo -E bash \
    && sudo apt-get install -y moonlight-qt
fi
command -v moonlight-qt >/dev/null || echo "!! moonlight-qt не установился - см. README, раздел 'Если ничего не работает'"
command -v wlrctl >/dev/null || echo "!! wlrctl не установился"

say "Ссылки в $BIN"
mkdir -p "$BIN"
chmod +x "$ROOT"/pi/*.sh
BK="$BIN/sm-backup-$(date +%Y%m%d-%H%M%S)"
for f in "$ROOT"/pi/sm-*.sh; do
  n=$(basename "$f")
  if [ -e "$BIN/$n" ] && [ ! -L "$BIN/$n" ]; then mkdir -p "$BK"; mv "$BIN/$n" "$BK/"; fi
  ln -sf "$f" "$BIN/$n"
done
[ -d "$BK" ] && echo "Старые копии скриптов убраны в $BK"

say "SSH-ключи Windows из keys/"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
OPTS="command=\"$BIN/sm-ssh.sh\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty"
added=0
for k in "$ROOT"/keys/*.pub; do
  [ -f "$k" ] || continue
  line=$(head -1 "$k" | tr -d '\r')
  blob=$(echo "$line" | awk '{print $2}')
  [ -z "$blob" ] && continue
  if grep -qF -- "$blob" "$HOME/.ssh/authorized_keys"; then
    echo "уже есть: $(basename "$k")"
  else
    echo "$OPTS $line" >> "$HOME/.ssh/authorized_keys"; added=$((added+1)); echo "добавлен: $(basename "$k")"
  fi
done
[ -z "$(ls "$ROOT"/keys/*.pub 2>/dev/null)" ] && echo "В keys/ нет ключей: сначала запусти install-windows.ps1 на Windows"

say "Адреса и ярлыки"
for n in windows pi; do
  [ -f "$ROOT/hosts/$n.manual.txt" ] || { [ -f "$ROOT/hosts/$n.manual.example.txt" ] && cp "$ROOT/hosts/$n.manual.example.txt" "$ROOT/hosts/$n.manual.txt"; }
done
D="$ROOT/pi"; . "$D/sm-common.sh"
write_pi_auto
mkdir -p "$HOME/.local/share/applications"
mk() { # имя файла, заголовок, команда
  cat > "$HOME/.local/share/applications/$1.desktop" <<DEOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$BIN/$3
Icon=video-display
Terminal=false
Categories=Utility;
DEOF
}
mk second-monitor-toggle "Второй монитор: переключить" sm-toggle.sh
mk second-monitor-start  "Второй монитор: включить"    sm-start.sh
mk second-monitor-stop   "Второй монитор: выключить"   sm-stop.sh
say "Автообновление адресов Pi (таймер раз в 10 минут)"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/sm-hosts.service" <<SEOF
[Unit]
Description=Second monitor: обновить адреса Pi в hosts/pi.auto.txt
[Service]
Type=oneshot
ExecStart=$BIN/sm-hosts.sh refresh
SEOF
cat > "$HOME/.config/systemd/user/sm-hosts.timer" <<SEOF
[Unit]
Description=Second monitor: периодическое обновление адресов Pi
[Timer]
OnBootSec=1min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
SEOF
systemctl --user daemon-reload 2>/dev/null
systemctl --user enable --now sm-hosts.timer 2>/dev/null && echo "таймер включён" || echo "таймер не включился (не страшно: адреса обновляются и при каждом запуске стрима)"

"$BIN/sm-panel.sh" start   # заодно запоминает окружение панели

echo
echo "Готово. Дальше (один раз):"
echo "  1) спаривание с Windows:  pkill moonlight-qt; QT_QPA_PLATFORM=offscreen moonlight-qt pair АДРЕС_WINDOWS 2>&1 | grep -iv -E 'DRM|HDMI1|SDL |Qt '"
echo "     PIN из вывода ввести в веб-панели Apollo (https://localhost:47990, вкладка PIN) и выдать права клиенту"
echo "  2) проверка:               sm-doctor.sh"
echo "  3) кнопки на панель Pi:    ПКМ по панели -> Панель -> Добавить новые элементы -> Лаунчер -> найти 'Второй монитор'"
