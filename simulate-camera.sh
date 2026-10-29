#!/usr/bin/env bash
# The same 640x360/15fps H.264 MPEG-TS ball source used during the bench tests.
set -euo pipefail

fail() {
    printf 'simulate-camera: %s\n' "$2" >&2
    exit "$1"
}
check_plugins() {
    command -v gst-launch-1.0 >/dev/null || fail 69 "Install gstreamer1.0-tools."
    command -v gst-inspect-1.0 >/dev/null || fail 69 "Install gstreamer1.0-tools."
    local element
    for element in videotestsrc capsfilter x264enc h264parse mpegtsmux udpsink; do
        gst-inspect-1.0 "$element" >/dev/null 2>&1 ||
            fail 69 "Missing $element. Install the simulator packages listed in README.md."
    done
}
if [[ "${1:-}" == --check-plugins ]]; then
    [[ $# -eq 1 ]] || fail 64 "Usage: simulate-camera.sh DESTINATION_IP [UDP_PORT]"
    check_plugins
    printf 'All simulator GStreamer elements are available.\n'
    exit 0
fi
[[ $# -ge 1 && $# -le 2 ]] ||
    fail 64 "Usage: simulate-camera.sh DESTINATION_IP [UDP_PORT]"
destination="$1"
port="${2:-15004}"
# Accept a literal IP or simple DNS hostname, without URI/shell/pipeline syntax.
[[ "$destination" =~ ^[[:alnum:]:][[:alnum:].:%_-]*$ ]] ||
    fail 64 "Supply a destination IP or hostname, without a URL scheme or brackets."
[[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] ||
    fail 64 "UDP_PORT must be a decimal integer from 1 to 65535."
(( port <= 65535 )) || fail 64 "UDP_PORT must be 1..65535."
check_plugins
printf 'Sending simulated camera video to %s UDP %s. Stop with Ctrl+C.\n' "$destination" "$port"
exec gst-launch-1.0 -e \
    videotestsrc is-live=true pattern=ball ! \
    video/x-raw,format=I420,width=640,height=360,framerate=15/1 ! \
    x264enc tune=zerolatency speed-preset=ultrafast bitrate=1000 key-int-max=15 ! \
    h264parse ! mpegtsmux alignment=7 ! \
    udpsink "host=$destination" "port=$port" sync=false
