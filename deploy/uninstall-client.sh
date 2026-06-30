#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.local/share/simplepresent"
DATA_DIR="$HOME/Documents/simplepresent"

APP_ID="be.heister.simplepresent"
DESKTOP_ENTRY_NAME="$APP_ID.desktop"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR_128="$HOME/.local/share/icons/hicolor/128x128/apps"
ICON_NAME="simple_present"

# If running interactively and not forced, ask whether to remove data
echo "The uninstall will remove the application files and menu/desktop entries."
read -r -p "Also delete data files ($JSON)? [y/N] " resp
resp="${resp:-n}"
case "$resp" in
  [Yy]* ) REMOVE_DATA=1 ;;
  * ) REMOVE_DATA=0 ;;
esac

# Remove target directory
if [ -d "$TARGET_DIR" ]; then
  echo "Removing installed files from $TARGET_DIR..."
  rm -rf "$TARGET_DIR"
else
  echo "No installation directory found at $TARGET_DIR"
fi

# Remove menu entry
if [ -f "$APPS_DIR/$DESKTOP_ENTRY_NAME" ]; then
  echo "Removing menu entry: $APPS_DIR/$DESKTOP_ENTRY_NAME"
  rm -f "$APPS_DIR/$DESKTOP_ENTRY_NAME"
fi

# Remove desktop shortcut
if [ -f "$HOME/Desktop/$DESKTOP_ENTRY_NAME" ]; then
  echo "Removing desktop entry: $HOME/Desktop/$DESKTOP_ENTRY_NAME"
  rm -f "$HOME/Desktop/$DESKTOP_ENTRY_NAME"
fi

# Remove installed icon
if [ -f "$ICON_DIR_128/$ICON_NAME.png" ]; then
  echo "Removing icon: $ICON_DIR_128/$ICON_NAME.png"
  rm -f "$ICON_DIR_128/$ICON_NAME.png"
fi

# Optionally remove user data files
if [ "$REMOVE_DATA" -eq 1 ]; then
  echo "Removing user data files..."
  if [ -d "$DATA_DIR" ]; then
    rm -rf "$DATA_DIR"
    echo "Removed $DATA_DIR"
  else
    echo "$DATA_DIR not found"
  fi
else
  echo "User data preserved. To delete data run with --remove-data or rerun with --yes --remove-data."
fi

echo "Uninstall finished."
exit 0
