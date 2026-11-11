#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"
APPS_DIR="${HOME}/.local/share/applications"

mkdir -p "$ICON_DIR" "$APPS_DIR"
cp "$APP_DIR/data/resong.png" "$ICON_DIR/dev.resong.resong.png"

sed "s|^Exec=.*|Exec=${APP_DIR}/resong %U|" \
  "$APP_DIR/dev.resong.resong.desktop" > "$APPS_DIR/dev.resong.resong.desktop"

chmod +x "$APP_DIR/resong"
update-desktop-database "$APPS_DIR" 2>/dev/null || true
echo "resong instalado no menu do usuario em ${APP_DIR}"
