#!/bin/sh
set -eu

export HOME=/tmp/home
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

cleanup() {
    rm -f /tmp/agentbox-ready
    kill "${OPENBOX_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
    wait "${OPENBOX_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
}

terminate() {
    trap - EXIT INT TERM
    cleanup
    exit 0
}

trap cleanup EXIT
trap terminate INT TERM

Xvfb "$DISPLAY" -screen 0 640x480x24 -nolisten tcp -noreset &
XVFB_PID=$!

attempt=0
until xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 100 ]; then
        echo "Xvfb did not become ready" >&2
        exit 1
    fi
    sleep 0.05
done

openbox --sm-disable >/tmp/openbox.log 2>&1 &
OPENBOX_PID=$!

attempt=0
while :; do
    wm_info=$(xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null || true)
    case "$wm_info" in
        *"window id #"*) break ;;
    esac
    if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
        echo "Openbox exited before becoming ready" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 100 ]; then
        echo "Openbox did not become ready" >&2
        exit 1
    fi
    sleep 0.05
done

touch /tmp/agentbox-ready

while :; do
    sleep 3600 &
    wait $!
done
