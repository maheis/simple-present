#!/usr/bin/env bash
set -euo pipefail

# Generates Android launcher (adaptive + legacy) and notification icons
# from provided SVGs in assets/icons.
# Usage: ./generate-android-icons.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG_DIR="$PROJECT_ROOT/assets/icons"
ANDROID_RES="$PROJECT_ROOT/android/app/src/main/res"

SVG_FOREGROUND="$SVG_DIR/color_transparent_icon.svg"
SVG_BACKGROUND="$SVG_DIR/color_teal_icon.svg"
SVG_NOTIFICATION="$SVG_DIR/white_transparent_icon.svg"

# Density map and sizes (launcher legacy: mdpi=48... ; notification mdpi=24...)
declare -A LAUNCHER_SIZES=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
declare -A NOTIF_SIZES=( [mdpi]=24 [hdpi]=36 [xhdpi]=48 [xxhdpi]=72 [xxxhdpi]=96 )

# Find an SVG->PNG converter
if command -v rsvg-convert >/dev/null 2>&1; then
  CONVERTER="rsvg-convert"
  CONV_ARGS="-w"
elif command -v inkscape >/dev/null 2>&1; then
  CONVERTER="inkscape"
  CONV_ARGS="--export-width"
elif command -v convert >/dev/null 2>&1; then
  CONVERTER="convert"
  CONV_ARGS="-resize"
else
  echo "No SVG converter found. Please install 'rsvg-convert' (librsvg), 'inkscape', or ImageMagick 'convert'." >&2
  exit 2
fi

mkdir -p "$ANDROID_RES"

# Copy source SVGs into res/raw for reference
mkdir -p "$ANDROID_RES/raw"
if [ -f "$SVG_FOREGROUND" ]; then cp "$SVG_FOREGROUND" "$ANDROID_RES/raw/foreground_icon.svg"; fi
if [ -f "$SVG_BACKGROUND" ]; then cp "$SVG_BACKGROUND" "$ANDROID_RES/raw/background_icon.svg"; fi
if [ -f "$SVG_NOTIFICATION" ]; then cp "$SVG_NOTIFICATION" "$ANDROID_RES/raw/notification_icon.svg"; fi

# Create mipmap dirs and generate launcher PNGs (legacy, fully opaque)
for d in "mdpi" "hdpi" "xhdpi" "xxhdpi" "xxxhdpi"; do
  DIR="$ANDROID_RES/mipmap-$d"
  mkdir -p "$DIR"
  size=${LAUNCHER_SIZES[$d]}
  if [ -f "$SVG_BACKGROUND" ]; then
    OUT="$DIR/ic_launcher.png"
    echo "Generating $OUT ($size)x$size from non-transparent background SVG"
    if [ "$CONVERTER" = "rsvg-convert" ]; then
      rsvg-convert -w "$size" "$SVG_BACKGROUND" -o "$OUT"
    elif [ "$CONVERTER" = "inkscape" ]; then
      inkscape "$SVG_BACKGROUND" $CONV_ARGS="$size" -o "$OUT"
    else
      convert "$SVG_BACKGROUND" -resize ${size}x${size} "$OUT"
    fi
  fi
  # create round copy same as launcher
  if [ -f "$SVG_BACKGROUND" ]; then
    OUTR="$DIR/ic_launcher_round.png"
    cp -f "$DIR/ic_launcher.png" "$OUTR"
  fi
done

# Generate notification icons
for d in "mdpi" "hdpi" "xhdpi" "xxhdpi" "xxxhdpi"; do
  DIR="$ANDROID_RES/drawable-$d"
  mkdir -p "$DIR"
  size=${NOTIF_SIZES[$d]}
  if [ -f "$SVG_NOTIFICATION" ]; then
    OUT="$DIR/ic_stat_notify.png"
    echo "Generating $OUT ($size)x$size from notification SVG"
    if [ "$CONVERTER" = "rsvg-convert" ]; then
      rsvg-convert -w "$size" "$SVG_NOTIFICATION" -o "$OUT"
    elif [ "$CONVERTER" = "inkscape" ]; then
      inkscape "$SVG_NOTIFICATION" $CONV_ARGS="$size" -o "$OUT"
    else
      convert "$SVG_NOTIFICATION" -resize ${size}x${size} "$OUT"
    fi
  fi
done

# Adaptive icon: put foreground/background bitmaps into mipmap-anydpi-v26
AD_DIR="$ANDROID_RES/mipmap-anydpi-v26"
mkdir -p "$AD_DIR"
# foreground should stay transparent; do not copy full launcher PNG here
if [ -f "$SVG_FOREGROUND" ]; then
  FG_OUT="$AD_DIR/ic_launcher_foreground.png"
  if [ "$CONVERTER" = "rsvg-convert" ]; then
    rsvg-convert -w 192 "$SVG_FOREGROUND" -o "$FG_OUT"
  elif [ "$CONVERTER" = "inkscape" ]; then
    inkscape "$SVG_FOREGROUND" $CONV_ARGS=192 -o "$FG_OUT"
  else
    convert "$SVG_FOREGROUND" -resize 192x192 "$FG_OUT"
  fi
fi
if [ -f "$SVG_BACKGROUND" ]; then
  # generate a background image at 192px
  BG_OUT="$AD_DIR/ic_launcher_background.png"
  if [ "$CONVERTER" = "rsvg-convert" ]; then
    rsvg-convert -w 192 "$SVG_BACKGROUND" -o "$BG_OUT"
  elif [ "$CONVERTER" = "inkscape" ]; then
    inkscape "$SVG_BACKGROUND" $CONV_ARGS=192 -o "$BG_OUT"
  else
    convert "$SVG_BACKGROUND" -resize 192x192 "$BG_OUT"
  fi
fi

# Create adaptive icon XML files
cat > "$AD_DIR/ic_launcher.xml" <<EOF
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@mipmap/ic_launcher_background" />
  <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF

cat > "$AD_DIR/ic_launcher_round.xml" <<EOF
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@mipmap/ic_launcher_background" />
  <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF

# NOTE: Do NOT place ic_launcher.xml inside mipmap-{dpi} folders when ic_launcher.png
# already exists there — that causes "Duplicate resources" at Gradle merge time.
# Adaptive XMLs belong only in mipmap-anydpi-v26/.

# Remove placeholder default drawable if present; density PNGs should be used.
rm -f "$ANDROID_RES/drawable/ic_stat_notify.xml"

echo "Icon generation finished. Please review files under $ANDROID_RES/* and commit them."
