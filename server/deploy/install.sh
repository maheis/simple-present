#!/usr/bin/env bash
set -euo pipefail

# Simple install script for SimplePresent server (requires sudo)
# Installs binary to /usr/local/bin, config to /etc/simplepresent, creates data dir and systemd unit.

BIN=./simplepresent
INSTALL_BIN=/usr/local/bin/simplepresent
SYSTEMD_UNIT=./systemd/simplepresent.service
SYSTEMD_TARGET=/etc/systemd/system/simplepresent.service
ETC_DIR=/etc/simplepresent
ETC_CONFIG=${ETC_DIR}/config.json
DATA_DIR=/var/lib/simplepresent

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (or with sudo)" >&2
  exit 1
fi

if [ ! -f "$BIN" ]; then
  echo "Binary $BIN not found. Build first: cd server && go build -o simplepresent" >&2
  exit 1
fi

echo "Installing binary to ${INSTALL_BIN}"
install -m 0755 "$BIN" "$INSTALL_BIN"

echo "Creating user/group 'simplepresent' if missing"
if ! id -u simplepresent >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin simplepresent || true
fi

echo "Creating data dir ${DATA_DIR}"
mkdir -p "$DATA_DIR"
chown simplepresent:simplepresent "$DATA_DIR"
chmod 0755 "$DATA_DIR"

echo "Installing config to ${ETC_CONFIG} (only if missing)"
mkdir -p "$ETC_DIR"
if [ ! -f "$ETC_CONFIG" ]; then
  install -m 0644 ./etc/config.json.example "$ETC_CONFIG"
  echo "Wrote example config to $ETC_CONFIG - edit as needed"
else
  echo "$ETC_CONFIG already exists - leaving it in place"
fi

echo "Installing systemd unit to ${SYSTEMD_TARGET}"
install -m 0644 "$SYSTEMD_UNIT" "$SYSTEMD_TARGET"

echo "Reloading systemd and enabling service"
systemctl daemon-reload
systemctl enable --now simplepresent.service

echo "Install complete. Check 'journalctl -u simplepresent -f' for logs."
