# Compass-Relay — Ubuntu 24.04 deployment

This folder packages the fixed relay exercised on a Raspberry Pi 5, 8 GB,
running Ubuntu 24.04. Its job is to receive **H.264 video inside MPEG-TS over
UDP**, extract the H.264, and publish it to **Compass using RTSP over TCP**.
It does not decode or re-encode the video.

The pipeline and restart policy were exercised on the Pi. This installer,
dedicated service account, and configuration wrapper are new; validate their
first installation using the short checks below. This is a reproducible install
procedure, not a bit-for-bit OS image or a claim of completed field acceptance.

Bundle validation: Bash syntax passed for all scripts; stubbed executable tests
confirmed the relay arguments match Cade's reference (with the tested `-e` flag
and simulation URL), checked configuration/plugin failure handling, and verified
the simulator arguments. `systemd-analyze verify` accepted the unit with its
executable path pointed at the staged runtime. Live GStreamer, the privileged
installer, and Pi boot behavior were not run in the packaging environment.

## Current status — October 15, 2026

| Check | Observed result |
|---|---|
| Pi-local simulated video to Compass | Worked; clean picture during the local test. |
| Laptop simulator through ZeroTier to Pi to Compass | Worked; intermittent corruption/hiccups observed. |
| Sender stopped and restarted | Picture recovered without restarting the Pi relay or refreshing Compass. |
| Compass uplink interrupted with the original bare pipeline | GStreamer exited; manual restart required. |
| Same interruption under the systemd service | Retries continued and the picture returned after connectivity was restored. |
| Pi reboot | Relay and picture returned automatically. |
| Laptop simulator with local parsing | Seven minutes with no reported warnings. |
| UDP iperf test to Pi | 30 seconds, 1 Mbit/s, 1316-byte datagrams: 0/2850 lost; final jitter 0.300 ms. |
| Actual laptop stream parsed on Pi with publishing stopped | No reported warnings. |
| Two parsing branches with Compass publishing | Clean during the reported run following Wi-Fi relocation/reconnection. |
| Normal relay after Wi-Fi change | Improved substantially; occasional hiccups remain. |

**Open issue:** sustained video quality under the shared office Wi-Fi conditions.
Wi-Fi conditions are a plausible contributor, but the exact cause has not been
proven. The decision was to proceed with packaging and revisit quality on a
stable network and with a real camera. No buffer, queue, or codec tuning is
presented here as a proven fix.

## Files

| File | Purpose |
|---|---|
| `install.sh` | Install Ubuntu packages, service account, runtime, and unit. |
| `relay.env.example` | Destination URL and UDP listening port. |
| `relay.sh` | Validate configuration/plugins and execute the tested pipeline. |
| `compass-relay.service` | Boot startup and restart after process exit. |
| `simulate-camera.sh` | The ball-pattern source used for the bench tests. |

This folder can be copied into `deploy/compass-relay/` in the existing
`push-to-compass` repo. Use this folder's installer for this task. The original
root installer, Rust application, and `mission_config` integration are not used.
The repo's older `deploy/compass-relay.service`, if present, is a bench artifact;
the service source for this deployment is the one alongside this README.

## Install on a fresh Pi or update the bench Pi

Start with Ubuntu 24.04 and working network access. Set up the camera-side
network and internet connection using the normal team process. ZeroTier is
optional; it was used to bridge the office test networks.

If the downloaded archive is in the Pi's home directory:

```bash
mkdir -p ~/Projects/push-to-compass
cd ~/Projects/push-to-compass
unzip ~/push-to-compass-ubuntu24.zip
sudo bash deploy/compass-relay/install.sh
```

If `unzip` is missing, install it with `sudo apt-get install -y unzip`.
The archive adds this deployment folder; it does not replace the repo's root
files. When updating a previous copy of this folder, review and accept the
archive's overwrite prompts.

The installer installs:

```text
gstreamer1.0-tools
gstreamer1.0-plugins-base
gstreamer1.0-plugins-good
gstreamer1.0-plugins-bad
gstreamer1.0-plugins-ugly
gstreamer1.0-rtsp
```

`plugins-ugly` supplies the simulator's x264 encoder. `plugins-bad` supplies
the H.264 parser and MPEG-TS elements. The separate `gstreamer1.0-rtsp` package
is needed for the publishing sink. No compiler or Rust build is required.

On the existing Pi, where these packages are already installed, this is faster:

```bash
sudo bash deploy/compass-relay/install.sh --skip-packages
```

Both modes check for the required GStreamer elements. The installer:

- Creates an unprivileged `compass-relay` service account.
- Installs the runtime under `/usr/local/lib/compass-relay/`.
- Installs `/etc/systemd/system/compass-relay.service`.
- Creates `/etc/compass-relay/relay.env` only when absent.
- Backs up an existing unit, runtime, and configuration under
  `/var/backups/compass-relay/<installation-id>/`.
- Records actual package versions in
  `/var/lib/compass-relay/installed-versions.txt`.
- Leaves any current relay process running until you explicitly restart it.

Review the configuration:

```bash
sudo nano /etc/compass-relay/relay.env
```

The initial configuration is:

```ini
COMPASS_URL="rtsp://compass.mchmr.us:554/elijah-pi-sim-test/group/AFCENT"
UDP_PORT=15004
```

That URL is the dedicated bench stream already used successfully in Compass.
Give each concurrent publisher a distinct, agreed stream name. Use the
appropriate operational destination when switching to a real camera.
The file contains literal assignments: no `export`, commands, or variable
substitution. The service reads it through systemd's `EnvironmentFile`.
The port must be between 1024 and 65535; the tested value is 15004.

Stop any manually launched diagnostic relay with Ctrl+C, then activate:

```bash
sudo systemctl enable compass-relay.service
sudo systemctl restart compass-relay.service
systemctl status compass-relay.service --no-pager
```

`restart` also starts an inactive service. Use it here so an already-running
bench service picks up the new unit and configuration. An installer rerun
preserves the existing configuration and does not apply runtime changes until
the service is restarted.

## Quick verification

First use a local source on the Pi to check the installed service:

```bash
cd ~/Projects/push-to-compass
bash deploy/compass-relay/simulate-camera.sh 127.0.0.1
```

Confirm the ball appears in the dedicated Compass stream. In another terminal:

```bash
sudo journalctl -u compass-relay.service -n 30 --no-pager
```

A running service alone does not prove video is arriving or visible in Compass.
Confirm the picture as well as service status. Stop the local simulator with
Ctrl+C before starting another sender to the same listening port.

To test from an Ubuntu laptop, copy this folder there and install the simulator
packages on the laptop:

```bash
sudo apt-get update
sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly
bash deploy/compass-relay/simulate-camera.sh PI_REACHABLE_IP
```

Replace `PI_REACHABLE_IP` with the Pi's reachable address: its assigned
ZeroTier address for that test arrangement, or its camera-network address
when directly connected. It is not a physical peer endpoint from
`zerotier-cli peers`. For a changed receiver port, pass that port as the
second simulator argument.

The simulator produces 640×360 video at 15 fps, with a 1000 kbit/s encoder
target, a 15-frame maximum keyframe interval, and seven TS packets per UDP
datagram (1316 bytes). The actual encoded bitrate can differ from the target.
Its settings match the earlier test commands, including `sync=false`.

The next two checks are for the newly packaged service's first installation;
the earlier bench service already passed source recovery and reboot tests:

1. Stop and restart the simulator. Confirm the picture returns without
   restarting the relay or refreshing the browser.
2. When convenient, reboot the Pi with the laptop simulator sending.
   Confirm the service starts and the picture returns after networking recovers.

An optional process-recovery check on the dedicated bench stream is:

```bash
sudo systemctl kill --kill-whom=main --signal=SIGKILL compass-relay.service
sudo journalctl -u compass-relay.service -n 30 --no-pager
```

This deliberately interrupts the test stream. The configured restart delay is
five seconds, followed by connection setup. It checks process restart, not the
full behavior of every possible network outage.

## Connect a real camera

The reference was Cade's script for the KHA K1000's Trillium HD-40 output.
This package supports that same input contract; the camera hardware itself has
not been exercised in this bench setup.

1. Put the Pi on a network that can receive the camera's traffic.
2. Configure the camera/aircraft encoder to send **H.264 inside MPEG-TS over
   unicast UDP** to the Pi's address on that network, port **15004**.
3. Give the Pi internet routing and DNS access to the configured Compass host,
   including outbound TCP to the endpoint's RTSP port (554 in the tested URL).
4. Stop the simulator, select the agreed Compass stream in `relay.env`, and
   restart the service.
5. Verify picture quality and recovery using the actual camera and deployment
   network. Record its resolution, frame rate, bitrate, keyframe interval, and
   addressing in the deployment notes.

The input listens on the Pi's available IPv4 interfaces; no camera IP is placed
in this relay configuration. This is a passive UDP receiver, so the sender must
be configured to target it. The Pi does not need to route the camera's packets
to the internet: the relay originates its own Compass connection. Configure
the Pi's routes so Compass uses the intended uplink.

Firewall/network policy must permit the incoming camera UDP traffic and the
outgoing Compass TCP connection. The installer does not change firewall rules,
Wi-Fi settings, routes, IP forwarding, NAT, or ZeroTier.

## Daily operation

```bash
# Status and recent messages
systemctl status compass-relay.service --no-pager
sudo journalctl -u compass-relay.service -n 60 --no-pager

# Follow only new messages; Ctrl+C closes the log viewer, not the relay
sudo journalctl -u compass-relay.service -n 0 -f

# Change destination/port, then apply
sudo nano /etc/compass-relay/relay.env
sudo systemctl restart compass-relay.service

# Stop now / prevent boot startup
sudo systemctl stop compass-relay.service
sudo systemctl disable compass-relay.service

# Enable boot startup and start now
sudo systemctl enable --now compass-relay.service
```

Silence in a following journal window can simply mean there are no new
messages. Disconnecting SSH does not stop the system service.

## Troubleshooting and limits

- **Missing packages:** some packages are in Ubuntu's Universe component.
  If apt says they have no installation candidate, enable Universe and rerun:
  `sudo apt-get install -y software-properties-common`, then
  `sudo add-apt-repository -y universe`. Check network access and apt errors
  before assuming this is the cause.
- **Missing `h264parse`:** install `gstreamer1.0-plugins-bad` on the machine
  reporting the error. Installing only `plugins-ugly` does not provide it.
- **Missing `rtspclientsink`:** install `gstreamer1.0-rtsp` on the Pi.
- **Service fails immediately with status 78:** fix the URL or port in
  `relay.env` and restart. Status 69 indicates a missing runtime/plugin.
  These configuration/dependency errors intentionally do not retry forever.
- **No picture with an active service:** confirm the sender is running,
  targets the Pi's correct address/port, and emits the specified format.
  Inspect `sudo ss -u -a -n -m -p '( sport = :15004 )'` to confirm the listener.
  Check the logs and the configured Compass stream name.
- **Continuity warnings with damaged frames:** MPEG-TS packet continuity was
  broken somewhere before that demuxer. Network loss, reordering, or drops
  inside a queue can contribute. Do not suppress the warnings as a fix.
  Compare local and remote sources under the relevant traffic conditions.
- **Restart behavior:** systemd retries process exits after five seconds.
  Network detection and connection setup add their own delays. There is no
  media-arrival watchdog: a running but stalled pipeline is not automatically
  detected. `network-online.target` is not proof that Compass is reachable.
- **Queue behavior:** the original 10000-buffer, downstream-leaky queue is
  retained. It can accumulate delay and discard old data if it fills. Its
  long-term behavior at the actual camera bitrate remains to be validated.
- **Input/output scope:** H.264 video only. This pipeline does not forward
  KLV metadata or audio, pull an RTSP camera, depayload RTP, accept H.265,
  discover cameras, or adapt bitrates to a variable uplink.
- **Package versions:** apt installs the versions available from the Pi's
  configured Ubuntu repositories. The recorded version list provides
  provenance, but does not pin a fully immutable software image.

## Roll back the service change

The installer prints the backup directory when updating an existing setup.
For the current bench Pi, the backed-up unit contains the original inline
GStreamer pipeline. Set `backup_dir` to the actual directory printed:

```bash
backup_dir=/var/backups/compass-relay/REPLACE_WITH_ACTUAL_INSTALLATION_ID
sudo systemctl stop compass-relay.service
sudo cp -a "$backup_dir/compass-relay.service" /etc/systemd/system/compass-relay.service
sudo systemctl daemon-reload
sudo systemctl start compass-relay.service
```

If rolling back a later version of this packaged setup, also restore its
`runtime/` contents and `relay.env` from that same backup before restarting.
This restores the service/configuration, not apt package versions. For a fresh
install with no earlier service to restore, disable and stop the service.

## Primary references

- [Ubuntu 24.04 arm64 RTSP plugin package](https://packages.ubuntu.com/noble/arm64/gstreamer1.0-rtsp)
- [GStreamer queue limits and dropping behavior](https://gstreamer.freedesktop.org/documentation/coreelements/queue.html)
- [GStreamer H.264 parser](https://gstreamer.freedesktop.org/documentation/videoparsersbad/h264parse.html)
- [systemd service restart behavior](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
- [systemd environment-file configuration](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)

Source baseline: the supplied `push-to-compass` snapshot at `e99bcf5` and
`kha-hd40.sh`, with the separate simulation stream name established during
this session. No Portcullis components are required.
