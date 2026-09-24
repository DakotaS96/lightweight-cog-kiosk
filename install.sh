#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="lightweight-cog-kiosk"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIOSK_URL=""
KIOSK_USER="${SUDO_USER:-}"
REFRESH_MINUTES=30
ENABLE_REFRESH=1
HIDE_CURSOR=1

usage() {
    cat <<'EOF'
Usage:
  sudo ./install.sh --url URL [--user USER] [--refresh-minutes MINUTES]
  sudo ./install.sh --url URL [--user USER] --no-refresh [--show-cursor]

Options:
  --url URL                  Website displayed by Cog (required on first run)
  --user USER                Unprivileged kiosk user (default: invoking user)
  --refresh-minutes MINUTES  Full page reload interval (default: 30)
  --no-refresh               Do not install the periodic reload watchdog
  --hide-cursor              Hide the mouse cursor (default)
  --show-cursor              Show the cursor for interactive kiosks
  -h, --help                 Show this help
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

package_install_heartbeat() {
    local started_at=$SECONDS
    local elapsed minutes seconds

    while sleep 30; do
        elapsed=$((SECONDS - started_at))
        minutes=$((elapsed / 60))
        seconds=$((elapsed % 60))
        printf '\n[installer] Package installation is still active -- elapsed %dm %02ds.\n' \
            "$minutes" "$seconds"
        printf '[installer] Long pauses while Debian rebuilds manual-page indexes are normal.\n'
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            [[ $# -ge 2 ]] || die "--url requires a value"
            KIOSK_URL="$2"
            shift 2
            ;;
        --user)
            [[ $# -ge 2 ]] || die "--user requires a value"
            KIOSK_USER="$2"
            shift 2
            ;;
        --refresh-minutes)
            [[ $# -ge 2 ]] || die "--refresh-minutes requires a value"
            REFRESH_MINUTES="$2"
            shift 2
            ;;
        --no-refresh)
            ENABLE_REFRESH=0
            shift
            ;;
        --hide-cursor)
            HIDE_CURSOR=1
            shift
            ;;
        --show-cursor)
            HIDE_CURSOR=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Run this installer with sudo."
[[ -n "$KIOSK_USER" ]] || die "Use --user USER when sudo was not invoked by the kiosk user."
id "$KIOSK_USER" >/dev/null 2>&1 || die "User '$KIOSK_USER' does not exist."

if [[ -z "$KIOSK_URL" && -r /etc/default/$PROGRAM_NAME ]]; then
    # Reinstallation may reuse the existing URL. The file is root-controlled.
    # shellcheck disable=SC1091
    source "/etc/default/$PROGRAM_NAME"
fi

[[ "$KIOSK_URL" =~ ^https?://[^[:space:]]+$ ]] || \
    die "Provide a valid http:// or https:// URL with --url."
[[ "$REFRESH_MINUTES" =~ ^[1-9][0-9]*$ ]] || \
    die "--refresh-minutes must be a positive whole number."

source /etc/os-release
if [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
    die "This release targets Raspberry Pi OS/Debian Trixie. Found: ${PRETTY_NAME:-unknown}."
fi

KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
[[ -d "$KIOSK_HOME" ]] || die "Home directory for '$KIOSK_USER' was not found."

PACKAGES=(
    cog
    cage
    bubblewrap
    libgles2
    dbus-user-session
    gstreamer1.0-tools
    gstreamer1.0-alsa
    gstreamer1.0-plugins-base
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
    gstreamer1.0-libav
    fonts-dejavu-core
    fonts-liberation2
    fonts-noto-core
)

echo "Installing Cog, Cage, media support, fonts, and D-Bus support..."
apt-get update

package_install_heartbeat &
HEARTBEAT_PID=$!
trap 'kill "$HEARTBEAT_PID" 2>/dev/null || true' EXIT

if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
    trap - EXIT
    die "Package installation failed. Review the apt/dpkg messages above."
fi

kill "$HEARTBEAT_PID" 2>/dev/null || true
wait "$HEARTBEAT_PID" 2>/dev/null || true
trap - EXIT

# Cage 0.3.1 honors XCURSOR_THEME. Install a self-contained transparent
# Xcursor theme so unattended signage does not leave a pointer over content.
# The embedded file is a valid 1x1 fully transparent Xcursor image.
CURSOR_THEME="lightweight-cog-kiosk-transparent"
CURSOR_BASE="/usr/local/share/$PROGRAM_NAME/icons"
CURSOR_ROOT="$CURSOR_BASE/$CURSOR_THEME"
if [[ $HIDE_CURSOR -eq 1 ]]; then
    install -d -m 0755 "$CURSOR_ROOT/cursors"
    printf '%s' \
        'WGN1chAAAAAAAAEAAQAAAAIA/f8YAAAAHAAAACQAAAACAP3/GAAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAA=' \
        | base64 --decode > "$CURSOR_ROOT/cursors/left_ptr"
    chmod 0644 "$CURSOR_ROOT/cursors/left_ptr"

    CURSOR_ALIASES=(
        default arrow top_left_arrow pointer hand1 hand2 text xterm
        vertical-text crosshair cell help question_arrow progress wait watch
        left_ptr_watch move fleur all-scroll not-allowed no-drop copy alias
        context-menu ew-resize ns-resize nesw-resize nwse-resize col-resize
        row-resize grab grabbing zoom-in zoom-out
    )
    for cursor_name in "${CURSOR_ALIASES[@]}"; do
        ln -sfn left_ptr "$CURSOR_ROOT/cursors/$cursor_name"
    done

    printf '%s\n' \
        '[Icon Theme]' \
        'Name=Lightweight Cog Kiosk Transparent Cursor' \
        'Comment=Transparent cursor for unattended kiosk displays' \
        > "$CURSOR_ROOT/index.theme"
    chmod 0644 "$CURSOR_ROOT/index.theme"

    # Older Cage builds may request the literal theme name "default". Keep
    # that lookup inside this application's private cursor search path.
    ln -sfn "$CURSOR_THEME" "$CURSOR_BASE/default"
fi

install -d -m 0755 /etc/default
ESCAPED_URL="${KIOSK_URL//\\/\\\\}"
ESCAPED_URL="${ESCAPED_URL//\"/\\\"}"
{
    printf 'KIOSK_URL="%s"\n' "$ESCAPED_URL"
    printf 'KIOSK_HIDE_CURSOR="%s"\n' "$HIDE_CURSOR"
    if [[ $HIDE_CURSOR -eq 1 ]]; then
        printf 'XCURSOR_THEME="%s"\n' "$CURSOR_THEME"
        printf 'XCURSOR_PATH="%s"\n' "$CURSOR_BASE"
        printf 'XCURSOR_SIZE="24"\n'
    fi
} > "/etc/default/$PROGRAM_NAME"
chmod 0644 "/etc/default/$PROGRAM_NAME"

sed \
    -e "s|@KIOSK_USER@|$KIOSK_USER|g" \
    -e "s|@KIOSK_HOME@|$KIOSK_HOME|g" \
    "$SCRIPT_DIR/systemd/$PROGRAM_NAME.service.in" \
    > "/etc/systemd/system/$PROGRAM_NAME.service"

install -m 0755 \
    "$SCRIPT_DIR/scripts/$PROGRAM_NAME-refresh" \
    "/usr/local/sbin/$PROGRAM_NAME-refresh"

sed \
    -e "s|@KIOSK_USER@|$KIOSK_USER|g" \
    "$SCRIPT_DIR/systemd/$PROGRAM_NAME-refresh.service.in" \
    > "/etc/systemd/system/$PROGRAM_NAME-refresh.service"

sed \
    -e "s|@REFRESH_MINUTES@|$REFRESH_MINUTES|g" \
    "$SCRIPT_DIR/systemd/$PROGRAM_NAME-refresh.timer.in" \
    > "/etc/systemd/system/$PROGRAM_NAME-refresh.timer"

# Migrate the original test installation when present.
if systemctl list-unit-files kiosk-test.service >/dev/null 2>&1; then
    systemctl disable --now kiosk-test.service || true
fi

systemctl disable --now getty@tty1.service || true
systemctl daemon-reload
systemctl enable "$PROGRAM_NAME.service"
systemctl restart "$PROGRAM_NAME.service"

if [[ $ENABLE_REFRESH -eq 1 ]]; then
    systemctl enable "$PROGRAM_NAME-refresh.timer"
    systemctl restart "$PROGRAM_NAME-refresh.timer"
else
    systemctl disable --now "$PROGRAM_NAME-refresh.timer" 2>/dev/null || true
fi

echo
echo "Installation complete."
echo "URL: $KIOSK_URL"
echo "User: $KIOSK_USER"
if [[ $HIDE_CURSOR -eq 1 ]]; then
    echo "Mouse cursor: hidden"
else
    echo "Mouse cursor: visible"
fi
if [[ $ENABLE_REFRESH -eq 1 ]]; then
    echo "Page reload watchdog: every $REFRESH_MINUTES minutes"
else
    echo "Page reload watchdog: disabled"
fi
echo
echo "Check status with:"
echo "  systemctl status $PROGRAM_NAME.service --no-pager"
echo "  systemctl status $PROGRAM_NAME-refresh.timer --no-pager"
