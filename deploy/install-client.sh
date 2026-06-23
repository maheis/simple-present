#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${1:-$SCRIPT_DIR}"
TARGET_DIR="$HOME/.local/share/simplepresent"
DATA_DIR="$HOME/Documents"
JSON_TASKS="$DATA_DIR/simplepresent_tasks.json"
JSON_TIMES="$DATA_DIR/simplepresent_time_entries.json"

CREATE_MENU=0
CREATE_DESKTOP=0

print_usage() {
  cat <<'USAGE'
Usage: ./install-client.sh [--source DIR] [--menu] [--desktop] [--help]

Installs SimplePresent client files to ~/.local/share/simplepresent and
ensures JSON data files are located under ~/Documents.

Options:
  --source DIR     Source directory to install from (default: script dir)
  --menu           Install a start-menu entry (~/.local/share/applications)
  --desktop        Also place a desktop icon on the user's Desktop
  --help           Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      shift
      SRC_DIR="$1"
      ;;
    --menu)
      CREATE_MENU=1
      ;;
    --desktop)
      CREATE_DESKTOP=1
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 2
      ;;
  esac
  shift
done

echo "Source: $SRC_DIR"
echo "Target: $TARGET_DIR"

if [ ! -d "$SRC_DIR" ]; then
  echo "Source directory not found: $SRC_DIR" >&2
  exit 1
fi

echo "Creating target directory..."
mkdir -p "$TARGET_DIR"

echo "Copying files (excluding .git)..."
rsync -a --delete --exclude='.git' --exclude='build' "$SRC_DIR/" "$TARGET_DIR/"

echo "Creating launcher script..."
LAUNCHER="$TARGET_DIR/launch-simplepresent.sh"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${TARGET_DIR}"
if [ -x "./simplepresent" ]; then
  exec "./simplepresent" "${@-}"
fi
if command -v flutter >/dev/null 2>&1; then
  echo "No native binary found; attempting to run with flutter (requires SDK)."
  exec flutter run -d linux --release --target=lib/main.dart
fi
echo "No runnable binary found in ${TARGET_DIR}. Build a Linux binary and place it there or run the app via 'flutter run' from the source." >&2
exit 2
EOF
chmod 0755 "$LAUNCHER"

# If no explicit flags were provided, and we have a TTY, ask interactively
if [ "$CREATE_MENU" -eq 0 ] && [ "$CREATE_DESKTOP" -eq 0 ]; then
  if [ -t 0 ]; then
    read -r -p "Create start-menu entry? [Y/n] " resp
    resp="${resp:-Y}"
    case "$resp" in
      [Yy]* ) CREATE_MENU=1 ;;
      * ) CREATE_MENU=0 ;;
    esac

    read -r -p "Create desktop icon? [y/N] " resp2
    resp2="${resp2:-n}"
    case "$resp2" in
      [Yy]* ) CREATE_DESKTOP=1 ;;
      * ) CREATE_DESKTOP=0 ;;
    esac
  fi
fi

echo "Ensuring data directory and sample JSON files in $DATA_DIR..."
mkdir -p "$DATA_DIR"
if [ ! -f "$JSON_TASKS" ]; then
  echo '[]' > "$JSON_TASKS"
  echo "Created $JSON_TASKS"
else
  echo "$JSON_TASKS already exists; leaving in place"
fi
if [ ! -f "$JSON_TIMES" ]; then
  echo '[]' > "$JSON_TIMES"
  echo "Created $JSON_TIMES"
else
  echo "$JSON_TIMES already exists; leaving in place"
fi

ICON_PATH="$TARGET_DIR/assets/icon.png"
if [ ! -f "$ICON_PATH" ]; then
  # fallback to a generic icon name; desktop environments will substitute
  ICON_PATH=""
fi

DESKTOP_ENTRY_NAME="simplepresent.desktop"
DESKTOP_CONTENT="[Desktop Entry]\nName=SimplePresent\nComment=SimplePresent client\nExec=$LAUNCHER\nIcon=$ICON_PATH\nTerminal=false\nType=Application\nCategories=Utility;"

if [ "$CREATE_MENU" -eq 1 ]; then
  APPS_DIR="$HOME/.local/share/applications"
  mkdir -p "$APPS_DIR"
  printf "%b" "$DESKTOP_CONTENT" > "$APPS_DIR/$DESKTOP_ENTRY_NAME"
  chmod 0644 "$APPS_DIR/$DESKTOP_ENTRY_NAME"
  echo "Installed menu entry: $APPS_DIR/$DESKTOP_ENTRY_NAME"
fi

if [ "$CREATE_DESKTOP" -eq 1 ]; then
  DESKTOP_DIR="$HOME/Desktop"
  mkdir -p "$DESKTOP_DIR"
  printf "%b" "$DESKTOP_CONTENT" > "$DESKTOP_DIR/$DESKTOP_ENTRY_NAME"
  chmod 0644 "$DESKTOP_DIR/$DESKTOP_ENTRY_NAME"
  echo "Installed desktop icon: $DESKTOP_DIR/$DESKTOP_ENTRY_NAME"
fi

echo "Install complete. Launch with: $LAUNCHER"
echo "Data files: $JSON_TASKS and $JSON_TIMES"
echo "If you installed the menu entry, you can search for 'SimplePresent' in your application launcher."

exit 0
