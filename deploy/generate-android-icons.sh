#!/usr/bin/env bash
set -euo pipefail

# Generates Android launcher and notification icons from SVGs in assets/icons.
# All icon resources are PNGs — no XML drawables used.
# Usage: ./generate-android-icons.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG_DIR="$PROJECT_ROOT/assets/icons"
ANDROID_RES="$PROJECT_ROOT/android/app/src/main/res"

SVG_BACKGROUND="$SVG_DIR/color_teal_icon.svg"
SVG_NOTIFICATION="$SVG_DIR/white_transparent_icon.svg"

# Density map and sizes (launcher: mdpi=48 ... xxxhdpi=192; notification: mdpi=24 ... xxxhdpi=96)
declare -A LAUNCHER_SIZES=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
declare -A NOTIF_SIZES=( [mdpi]=24 [hdpi]=36 [xhdpi]=48 [xxhdpi]=72 [xxxhdpi]=96 )

# Find an SVG->PNG converter
if command -v rsvg-convert >/dev/null 2>&1; then
  CONVERTER="rsvg-convert"
elif command -v inkscape >/dev/null 2>&1; then
  CONVERTER="inkscape"
elif command -v convert >/dev/null 2>&1; then
  CONVERTER="convert"
else
  echo "No SVG converter found. Install 'rsvg-convert' (librsvg), 'inkscape', or ImageMagick." >&2
  exit 2
fi

svg_to_png() {
  local svg="$1" size="$2" out="$3"
  if [ "$CONVERTER" = "rsvg-convert" ]; then
    rsvg-convert -w "$size" "$svg" -o "$out"
  elif [ "$CONVERTER" = "inkscape" ]; then
    inkscape "$svg" --export-width="$size" -o "$out"
  else
    convert "$svg" -resize "${size}x${size}" "$out"
  fi
}

mkdir -p "$ANDROID_RES"

# --- Launcher icons (fully opaque, one per density) ---
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  DIR="$ANDROID_RES/mipmap-$d"
  mkdir -p "$DIR"
  size=${LAUNCHER_SIZES[$d]}
  echo "Launcher $d (${size}px)"
  svg_to_png "$SVG_BACKGROUND" "$size" "$DIR/ic_launcher.png"
  cp -f "$DIR/ic_launcher.png" "$DIR/ic_launcher_round.png"
done

# --- Notification icons (white glyph on transparent background, one per density) ---
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  DIR="$ANDROID_RES/drawable-$d"
  mkdir -p "$DIR"
  size=${NOTIF_SIZES[$d]}
  echo "Notification $d (${size}px)"
  svg_to_png "$SVG_NOTIFICATION" "$size" "$DIR/ic_stat_notify.png"
done

# --- Launcher background PNG (solid color, used as ic_launcher_background) ---
mkdir -p "$ANDROID_RES/drawable"
if command -v magick >/dev/null 2>&1; then
  magick -size 432x432 xc:"#00251a" "$ANDROID_RES/drawable/ic_launcher_background.png"
else
  convert -size 432x432 xc:"#00251a" "$ANDROID_RES/drawable/ic_launcher_background.png"
fi
echo "Background PNG generated"

# --- Splash screen PNG (white, replaces launch_background.xml) ---
if command -v magick >/dev/null 2>&1; then
  magick -size 1x1 xc:white "$ANDROID_RES/drawable/launch_background.png"
  magick -size 1x1 xc:white "$ANDROID_RES/drawable-v21/launch_background.png"
else
  convert -size 1x1 xc:white "$ANDROID_RES/drawable/launch_background.png"
  convert -size 1x1 xc:white "$ANDROID_RES/drawable-v21/launch_background.png"
fi
echo "Splash PNGs generated"

# --- Remove any stale XMLs that have been superseded by PNGs ---
rm -f "$ANDROID_RES/drawable/ic_launcher_background.xml"
rm -f "$ANDROID_RES/drawable/ic_stat_notify.xml"
rm -f "$ANDROID_RES/drawable/launch_background.xml"
rm -f "$ANDROID_RES/drawable-v21/launch_background.xml"
rm -rf "$ANDROID_RES/mipmap-anydpi-v26"

echo "Icon generation finished. Review files under $ANDROID_RES/* and commit them."
