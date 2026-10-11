#!/bin/bash
# Ограничитель SSH-ключа: ключ из keys/*.pub может выполнять ТОЛЬКО эти команды.
set -f
set -- $SSH_ORIGINAL_COMMAND
D=$(dirname "$(readlink -f "$0")")
case "$1" in
  start)  exec "$D/sm-start.sh" ;;
  toggle) exec "$D/sm-toggle.sh" ;;
  stop)   exec "$D/sm-stop.sh" ;;
  ping)   echo "pong $(hostname)" ;;
  *)      echo "denied" >&2; exit 1 ;;
esac
