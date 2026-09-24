#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="lightweight-cog-kiosk"

if [[ $EUID -ne 0 ]]; then
    echo "Run this uninstaller with sudo." >&2
    exit 1
fi

systemctl disable --now "$PROGRAM_NAME-refresh.timer" 2>/dev/null || true
systemctl disable --now "$PROGRAM_NAME.service" 2>/dev/null || true

rm -f "/etc/systemd/system/$PROGRAM_NAME.service"
rm -f "/etc/systemd/system/$PROGRAM_NAME-refresh.service"
rm -f "/etc/systemd/system/$PROGRAM_NAME-refresh.timer"
rm -f "/usr/local/sbin/$PROGRAM_NAME-refresh"

systemctl daemon-reload
systemctl enable --now getty@tty1.service || true

echo "Kiosk services removed."
echo "The URL configuration remains at /etc/default/$PROGRAM_NAME."
echo "Installed Debian packages were not removed."

