#!/usr/bin/env bash
# One input: H.264 in UDP MPEG-TS. One output: RTSP over TCP to Compass.
set -euo pipefail

fail() {
    printf 'compass-relay: %s\n' "$2" >&2
    exit "$1"
}

check_plugins() {
    command -v gst-launch-1.0 >/dev/null ||
        fail 69 "gst-launch-1.0 is missing; rerun install.sh."
    command -v gst-inspect-1.0 >/dev/null ||
        fail 69 "gst-inspect-1.0 is missing; rerun install.sh."
    local element
    for element in udpsrc tsparse queue tsdemux h264parse rtspclientsink; do
        gst-inspect-1.0 "$element" >/dev/null 2>&1 ||
            fail 69 "Missing GStreamer element: $element. Rerun install.sh."
    done
}

case "${1:-}" in
    --check-plugins)
        [[ $# -eq 1 ]] || fail 64 "Usage: relay.sh [--check-plugins]"
        check_plugins
        printf 'All relay GStreamer elements are available.\n'
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || fail 64 "Usage: relay.sh [--check-plugins]"
        ;;
    *) fail 64 "Usage: relay.sh [--check-plugins]" ;;
esac

UDP_PORT="${UDP_PORT:-15004}"
COMPASS_URL="${COMPASS_URL:-}"

[[ "$UDP_PORT" =~ ^[1-9][0-9]{0,4}$ ]] ||
    fail 78 "UDP_PORT must be a decimal integer from 1024 to 65535."
(( UDP_PORT >= 1024 && UDP_PORT <= 65535 )) ||
    fail 78 "UDP_PORT must be 1024..65535 for this unprivileged service."

[[ "$COMPASS_URL" =~ ^rtsp://[^/?#[:space:]]+/[^[:space:]]+$ ]] ||
    fail 78 "Set COMPASS_URL to a full rtsp://host:port/stream/path in /etc/compass-relay/relay.env."
[[ "$COMPASS_URL" != *'"'* && "$COMPASS_URL" != *"'"* && "$COMPASS_URL" != *\\* ]] ||
    fail 78 "COMPASS_URL must not contain literal quotes or backslashes; URL-encode these characters."
[[ "$COMPASS_URL" != *COMPASS_HOST* && "$COMPASS_URL" != *STREAM_NAME* ]] ||
    fail 78 "Replace the placeholder host and stream name in COMPASS_URL."

check_plugins
printf 'compass-relay: listening for H.264 MPEG-TS on UDP %s; publishing over RTSP/TCP.\n' "$UDP_PORT"

# Preserve the pipeline that was exercised on the Pi, including its queue limits.
# exec lets systemd track GStreamer directly and deliver SIGINT on service stop.
exec gst-launch-1.0 -e \
    udpsrc "port=$UDP_PORT" buffer-size=200000 caps=video/mpegts ! \
    tsparse parse-private-sections=false ! \
    queue max-size-buffers=10000 max-size-bytes=0 max-size-time=0 leaky=downstream ! \
    tsdemux ! h264parse ! queue ! \
    rtspclientsink protocols=tcp "location=$COMPASS_URL"
