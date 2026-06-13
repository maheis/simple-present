#!/usr/bin/env bash
set -euo pipefail

# Installer wrapper for SimplePresent server.
# Supports two modes:
# 1) Local: run from repository root: ./server/install.sh local
#    -> builds and runs ./server/deploy/install.sh
# 2) Remote: run via curl and provide repository URL:
#    curl -sL <raw-install-url> | sudo sh -s -- https://github.com/<owner>/<repo>.git [branch]
#    -> clones repo to a temp dir, builds and runs deploy/install.sh

REPO_URL=${1:-}
BRANCH=${2:-main}

if [ "${REPO_URL}" = "local" ]; then
  # Expect to be run from repo root
  if [ ! -f ./server/deploy/install.sh ]; then
    echo "deploy/install.sh not found. Run from repo root or use remote mode with a repo URL." >&2
    exit 1
  fi
  cd server
  echo "Building binary..."
  go build -o simplepresent || { echo "go build failed" >&2; exit 1; }
  echo "Running deploy/install.sh (needs root)"
  sudo ./deploy/install.sh
  exit 0
fi

if [ -z "$REPO_URL" ]; then
  cat <<'USAGE' >&2
Usage:
  Local: ./server/install.sh local
  Remote (via curl):
    curl -sL https://raw.githubusercontent.com/<owner>/<repo>/<branch>/server/install.sh | sudo sh -s -- https://github.com/<owner>/<repo>.git [branch]
USAGE
  exit 1
fi

TMPDIR=$(mktemp -d /tmp/simplepresent-install-XXXXXX)
echo "Cloning ${REPO_URL} (branch ${BRANCH}) to ${TMPDIR}"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMPDIR"
cd "$TMPDIR/server"

echo "Building binary..."
go build -o simplepresent || { echo "go build failed" >&2; exit 1; }

echo "Running deploy/install.sh (will use sudo)"
sudo ./deploy/install.sh

RET=$?
cd /
rm -rf "$TMPDIR"
exit $RET
