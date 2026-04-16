#!/bin/sh
# Clear stale process and lock file for a USB serial port.
# Usage: clear-port-locks.sh [tty.usbserial-XXXX]
# If no argument given, clears all USB serial locks.

PORT=${1:-""}

if [ -n "$PORT" ]; then
  CU_PORT=$(echo "$PORT" | sed 's|/dev/tty\.|/dev/cu.|; s|tty\.|cu.|')
  BASE=$(basename "$CU_PORT")
  PIDS=$(lsof 2>/dev/null | grep "$BASE" | awk '{print $2}' | sort -u)
  [ -n "$PIDS" ] && kill $PIDS 2>/dev/null && echo "Killed: $PIDS"
  rm -f "/private/tmp/LCK..${BASE}"
  echo "Cleared lock for $BASE"
else
  PIDS=$(lsof 2>/dev/null | grep "usbserial\|usbmodem" | awk '{print $2}' | sort -u)
  [ -n "$PIDS" ] && kill $PIDS 2>/dev/null && echo "Killed: $PIDS"
  rm -f /private/tmp/LCK..cu.usbserial-* /private/tmp/LCK..tty.usbserial-*
  echo "Cleared all USB serial locks"
fi
