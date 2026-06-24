#!/usr/bin/env bash
set -euo pipefail

# Uninstall script for simplepresent-server
# Reverses actions performed by deploy/install.sh

INSTALL_BIN=/usr/local/bin/simplepresent-server
DATA_DIR=/var/lib/simplepresent

ETC_DIR=/etc/simplepresent

SYSTEMD_TARGET=/etc/systemd/system/simplepresent-server.service

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (or with sudo)" >&2
  exit 1
fi

confirm() {
  read -r -p "$1 [y/N]: " resp
  case "$resp" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

echo "Stopping and disabling systemd service if present"
if systemctl list-unit-files --type=service | grep -q "^simplepresent-server\.service" 2>/dev/null || systemctl status simplepresent-server.service >/dev/null 2>&1; then
  systemctl stop simplepresent-server.service 2>/dev/null || true
  systemctl disable simplepresent-server.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
fi

if [ -f "$SYSTEMD_TARGET" ]; then
  if confirm "Remove systemd unit $SYSTEMD_TARGET?"; then
    rm -f "$SYSTEMD_TARGET"
    echo "Removed $SYSTEMD_TARGET"
    systemctl daemon-reload 2>/dev/null || true
  else
    echo "Left $SYSTEMD_TARGET in place"
  fi
fi

if [ -f "$INSTALL_BIN" ]; then
  if confirm "Remove installed binary $INSTALL_BIN?"; then
    rm -f "$INSTALL_BIN"
    echo "Removed $INSTALL_BIN"
  else
    echo "Left $INSTALL_BIN in place"
  fi
fi

if [ -d "$DATA_DIR" ]; then
  if confirm "Remove data directory $DATA_DIR (this will delete stored data)?"; then
    rm -rf "$DATA_DIR"
    echo "Removed $DATA_DIR"
  else
    echo "Left $DATA_DIR in place"
  fi
fi

if [ -d "$ETC_DIR" ]; then
    if confirm "Purge config directory $ETC_DIR? This is irreversible."; then
      rm -rf "$ETC_DIR"
      echo "Removed $ETC_DIR"
    else
      echo "Left $ETC_DIR in place"
    fi
fi

if id -u "simplepresent" >/dev/null 2>&1; then
if confirm "Remove system user simplepresent and its (now possibly missing) home?"; then
    userdel --system "simplepresent" 2>/dev/null || userdel "simplepresent" 2>/dev/null || true
    echo "User simplepresent removed (if it existed)"
else
    echo "Left user simplepresent in place"
fi
else
echo "User simplepresent does not exist, skipping"
fi

echo "Uninstall complete. If you removed the systemd unit, check 'systemctl status simplepresent-server' for leftovers."

exit 0
