#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${1:-$SCRIPT_DIR}"
TARGET_DIR="$HOME/.local/share/simplepresent"
DATA_DIR="$HOME/Documents"

echo "Source: $SRC_DIR"
echo "Target: $TARGET_DIR"

if [ ! -d "$SRC_DIR" ]; then
  echo "Source directory not found: $SRC_DIR" >&2
  exit 1
fi

if [ -d "$TARGET_DIR" ]; then
  read -r -p "Existing installation at $TARGET_DIR found. Update (remove and install)? [y/N] " resp
  if [[ "$resp" =~ ^[Yy] ]]; then
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    backup="${TARGET_DIR}.bak.$ts"
    echo "Backing up existing installation to $backup"
    mv "$TARGET_DIR" "$backup"
  else
    echo "Aborting installation."; exit 0
  fi
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

# Install icon into user icon theme if an asset exists
ICON_SRC=""
for candidate in "$TARGET_DIR/data/flutter_assets/assets/icons/color_transparent_icon.png" "$TARGET_DIR/assets/icons/color_transparent_icon.png" "$TARGET_DIR/color_transparent_icon.png"; do
  if [ -f "$candidate" ]; then
    ICON_SRC="$candidate"
    break
  fi
done

ICON_NAME="simple_present"
if [ -n "$ICON_SRC" ]; then
  ICON_DEST_DIR_128="$HOME/.local/share/icons/hicolor/128x128/apps"
  ICON_DEST_DIR_SCALABLE="$HOME/.local/share/icons/hicolor/scalable/apps"
  mkdir -p "$ICON_DEST_DIR_128" "$ICON_DEST_DIR_SCALABLE"
  ICON_DEST_PNG="$ICON_DEST_DIR_128/${ICON_NAME}.png"
  cp "$ICON_SRC" "$ICON_DEST_PNG"
  chmod 0644 "$ICON_DEST_PNG"
  echo "Installed icon(s) to $ICON_DEST_DIR_128 and $ICON_DEST_DIR_SCALABLE"
  # Prefer theme icon name for .desktop entries
  DESKTOP_ICON_VALUE="$ICON_NAME"
else
  DESKTOP_ICON_VALUE=""
fi

APP_ID="de.maheis.simplepresent"
DESKTOP_ENTRY_NAME="$APP_ID.desktop"
DESKTOP_CONTENT="[Desktop Entry]\nName=SimplePresent\nComment=SimplePresent client\nExec=$LAUNCHER\nIcon=$DESKTOP_ICON_VALUE\nTerminal=false\nType=Application\nCategories=Utility;\nStartupNotify=true\nStartupWMClass=SimplePresent\nX-GNOME-WMClass=SimplePresent"

if [ "$CREATE_MENU" -eq 1 ]; then
  APPS_DIR="$HOME/.local/share/applications"
  mkdir -p "$APPS_DIR"
  # Remove legacy desktop filename to avoid duplicate launcher entries.
  rm -f "$APPS_DIR/SimplePresent.desktop"
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
