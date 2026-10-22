#!/usr/bin/env bash
# install_services.sh: install systemd units for the project.
# Install:  sudo ./scripts/install_services.sh
# Remove:   sudo ./scripts/install_services.sh remove
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_USER="${SUDO_USER:-student}"
UNIT_DIR=/etc/systemd/system
LEGACY=(lrp-webload lrp-backup lrp-leak)   # units from an older design, removed if present

# Remove old units from the earlier design
for u in "${LEGACY[@]}"; do
  systemctl disable --now "$u.timer" 2>/dev/null || true
  rm -f "$UNIT_DIR/$u.service" "$UNIT_DIR/$u.timer"
done

if [ "${1:-}" = "remove" ]; then
  systemctl disable --now lrp-collector.timer 2>/dev/null || true
  systemctl disable --now lrp-webapp.service lrp-loadgen.service 2>/dev/null || true
  rm -f "$UNIT_DIR"/lrp-collector.* "$UNIT_DIR"/lrp-webapp.service "$UNIT_DIR"/lrp-loadgen.service
  systemctl daemon-reload
  echo "Removed."
  exit 0
fi

for cmd in stress-ng ab curl python3 tar; do
  command -v "$cmd" > /dev/null || {
    echo "Missing: $cmd (sudo apt install -y stress-ng apache2-utils curl python3)" >&2
    exit 1
  }
done

chmod +x "$PROJECT_DIR"/scripts/*.sh
sudo -u "$RUN_USER" mkdir -p "$PROJECT_DIR/data" "$PROJECT_DIR/logs" "$PROJECT_DIR/tmp_test"

cat > "$UNIT_DIR/lrp-collector.service" <<EOF
[Unit]
Description=Collect system metrics

[Service]
Type=oneshot
User=$RUN_USER
ExecStart=$PROJECT_DIR/scripts/collect_metrics.sh
EOF

cat > "$UNIT_DIR/lrp-collector.timer" <<EOF
[Unit]
Description=Run the metrics collector every minute

[Timer]
OnCalendar=minutely
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

cat > "$UNIT_DIR/lrp-webapp.service" <<EOF
[Unit]
Description=Test web app (controlled test service)
After=network.target

[Service]
User=$RUN_USER
ExecStart=/usr/bin/python3 $PROJECT_DIR/workloads/webapp.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > "$UNIT_DIR/lrp-loadgen.service" <<EOF
[Unit]
Description=Random load generator, one event at a time
After=lrp-webapp.service

[Service]
User=$RUN_USER
ExecStart=$PROJECT_DIR/scripts/generate_load.sh
Restart=always
RestartSec=5
OOMScoreAdjust=500

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lrp-collector.timer lrp-webapp.service lrp-loadgen.service
systemctl restart lrp-collector.timer lrp-webapp.service lrp-loadgen.service

echo "Installed. Active timers:"
systemctl list-timers 'lrp-*' --no-pager