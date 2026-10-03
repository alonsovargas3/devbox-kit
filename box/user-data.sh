#!/bin/bash
# devbox-kit cloud-init user-data. Rendered by `devbox provision`, which substitutes
# __DATA_VOLUME_ID__, __IDLE_MIN__, __ARCH__, __DEVBOX_NAME__. Runs once per instance and
# installs systemd units that run every boot.
#
# The persistent EBS data volume IS the dev environment; the instance is disposable.
# /data holds /home (bind mount), Docker's data-root, and containerd's root (Docker 29+
# keeps images in containerd, which ignores data-root). A fresh instance attached to the
# same volume comes back with the same repos, logins, images, and containers.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

cat >/etc/devbox.env <<EOF
DEVBOX_NAME=__DEVBOX_NAME__
DATA_VOL_SERIAL=$(echo '__DATA_VOLUME_ID__' | tr -d '-')
IDLE_MIN=__IDLE_MIN__
EOF

# --- data volume mount (every boot) -------------------------------------------
cat >/usr/local/sbin/devbox-data <<'EOF'
#!/bin/bash
# Wait for the data volume, format it only if it has no filesystem, mount /data,
# and bind /data/home over /home.
set -euo pipefail
. /etc/devbox.env
dev=""
for _ in $(seq 1 180); do
  dev="$(lsblk -dnpo NAME,SERIAL | awk -v s="$DATA_VOL_SERIAL" '$2==s{print $1}')"
  [[ -n "$dev" ]] && break
  sleep 2
done
[[ -n "$dev" ]] || { echo "devbox-data: volume $DATA_VOL_SERIAL never attached" >&2; exit 1; }

if ! blkid "$dev" >/dev/null 2>&1; then
  mkfs.ext4 -L devbox-data "$dev"
  fresh=1
fi
mkdir -p /data
mountpoint -q /data || mount -o defaults,noatime "$dev" /data

if [[ "${fresh:-0}" == 1 || ! -d /data/home ]]; then
  mkdir -p /data/home
  rsync -a /home/ /data/home/
fi
mountpoint -q /home || mount --bind /data/home /home
mkdir -p /data/docker /data/containerd
EOF
chmod 755 /usr/local/sbin/devbox-data

cat >/etc/systemd/system/devbox-data.service <<'EOF'
[Unit]
Description=Mount devbox persistent data volume
After=local-fs.target
Before=docker.service containerd.service ssh.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/devbox-data

[Install]
WantedBy=multi-user.target
EOF

# --- idle auto-stop (every 5 min) ---------------------------------------------
cat >/usr/local/sbin/devbox-idle-check <<'EOF'
#!/bin/bash
# devbox-idle-check [--explain] — stop the instance after IDLE_MIN minutes of no real use.
# Runs every 5 min from devbox-idle.timer. InstanceInitiatedShutdown=stop, so halt = stop.
#
# Busy if ANY of:
#   tty       a terminal (/dev/pts/N) was written or read within IDLE_MIN. Covers typing
#             and agents producing output. An idle Claude prompt writes nothing.
#   ssh       an SSH connection or command started within IDLE_MIN (sshd "Accepted", or
#             "Starting session", which LogLevel VERBOSE logs for every command, including
#             ones multiplexed over the laptop's ControlMaster connection). So laptop agents
#             running `ssh devbox 'cmd'` (no tty) count. A long-lived connection (e.g. Orca)
#             opened earlier doesn't. `devbox status`/`doctor`/`wip` count too.
#   load      15-min load average > 0.3
#   keepawake /data/keepawake touched within 12h (`devbox keepawake`), for agents that wait
#             silently on an API
#   boot      uptime < IDLE_MIN (grace after `devbox up`)
set -uo pipefail
. /etc/devbox.env
IDLE_MIN="${DEVBOX_IDLE_MIN:-${IDLE_MIN:-45}}"   # DEVBOX_IDLE_MIN overrides, for testing only
STATUS=/run/devbox-idle-status
now=$(date +%s); win=$((IDLE_MIN * 60)); why=""; last=0

for t in /dev/pts/[0-9]*; do
  [[ -e "$t" ]] || continue
  m=$(stat -c %Y "$t"); a=$(stat -c %X "$t"); (( a > m )) && m=$a
  (( m > last )) && last=$m
done
(( last > 0 && now - last < win )) && why="tty"
# Multiplexed commands only reach the journal at LogLevel VERBOSE; ensure it (self-healing).
v=/etc/ssh/sshd_config.d/50-devbox-verbose.conf
if [[ ! -f "$v" && $EUID -eq 0 ]]; then
  echo "LogLevel VERBOSE  # devbox-idle-check: logs every ssh command, incl. multiplexed ones" >"$v"
  sshd -t && systemctl reload ssh
fi
last_ssh=$(journalctl --since "-${IDLE_MIN} min" --no-pager -o short-unix \
  SYSLOG_IDENTIFIER=sshd SYSLOG_IDENTIFIER=sshd-session 2>/dev/null | awk '/ Accepted | Starting session: /{t=$1} END{printf "%d", t}')
(( last_ssh > 0 && now - last_ssh < win )) && why="${why:+$why,}ssh"
(( last_ssh > last )) && last=$last_ssh
awk '{exit !($3 > 0.3)}' /proc/loadavg && why="${why:+$why,}load"
if [[ -f /data/keepawake ]] && (( now - $(stat -c %Y /data/keepawake) < 43200 )); then
  why="${why:+$why,}keepawake"
fi
up=$(cut -d. -f1 /proc/uptime); (( up < win )) && why="${why:+$why,}boot"

if (( last > 0 && now - last < win )); then act="last terminal/ssh activity $(( (now - last) / 60 ))m ago"
else act="no terminal/ssh activity in the last ${IDLE_MIN}m"; fi
if [[ -n "$why" ]]; then verdict="busy ($why)"; else verdict="idle"; fi
echo "$verdict | $act | load15 $(cut -d' ' -f3 /proc/loadavg) | uptime $((up / 60))m | stops after ${IDLE_MIN}m idle" >"$STATUS"

if [[ "${1:-}" == --explain ]]; then cat "$STATUS"; exit 0; fi
if [[ -z "$why" ]]; then
  logger -t devbox-idle "idle: $act, low load, no keepawake — stopping instance"
  shutdown -h now
fi
EOF
chmod 755 /usr/local/sbin/devbox-idle-check

cat >/etc/systemd/system/devbox-idle.service <<'EOF'
[Unit]
Description=devbox idle check

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/devbox-idle-check
EOF

cat >/etc/systemd/system/devbox-idle.timer <<'EOF'
[Unit]
Description=devbox idle check every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now devbox-data.service
systemctl enable --now devbox-idle.timer

# --- Docker + containerd, both rooted on the persistent volume ------------------
apt-get update
apt-get install -y ca-certificates curl gnupg rsync
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=__ARCH__ signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  >/etc/apt/sources.list.d/docker.list
mkdir -p /etc/docker /etc/systemd/system/docker.service.d /etc/systemd/system/containerd.service.d
cat >/etc/docker/daemon.json <<'EOF'
{ "data-root": "/data/docker", "log-driver": "local" }
EOF
for svc in docker containerd; do
  cat >/etc/systemd/system/$svc.service.d/devbox.conf <<'EOF'
[Unit]
Requires=devbox-data.service
After=devbox-data.service
EOF
done
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# containerd's own root holds the image store on Docker 29+. Top-level key, so it must
# come before any [table]; replace the packaged commented default or prepend it.
# (The packaged file has only commented defaults and disabled_plugins, so dropping any
# root lines is safe.) `sed 1i` is a no-op on an empty file, hence the two branches.
cfg=/etc/containerd/config.toml
if [[ -s "$cfg" ]]; then
  sed -i -E '/^\s*#?\s*root\s*=/d' "$cfg"
  sed -i '1i root = "/data/containerd"' "$cfg"
else
  echo 'root = "/data/containerd"' >"$cfg"
fi
usermod -aG docker ubuntu
systemctl daemon-reload
systemctl restart containerd docker

touch /var/lib/devbox-bootstrapped
