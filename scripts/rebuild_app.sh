#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_PATH="$ROOT_DIR/BookGet GUI（v1.6-25.0417）.app"
APP_BIN="$APP_PATH/Contents/MacOS/BookGetGUILauncher"
HELPER_BIN="$APP_PATH/Contents/Resources/bin/bookget-web-login"
GUI_SRC="$ROOT_DIR/src/BookGetGUILauncher/bookget_gui_app.swift"
HELPER_SRC="$ROOT_DIR/src/bookget-web-login/main.swift"
WRAPPER_SRC="$ROOT_DIR/src/bookget-wrapper/bookget"
HELP_SRC="$ROOT_DIR/docs/BookGetGUIHelp.md"
HELP_DST="$APP_PATH/Contents/Resources/BookGetGUIHelp.md"
SITES_SRC="$ROOT_DIR/resources/sites.json"
TARGET="arm64-apple-macos14.0"
APP_VERSION="1.6"
APP_BUILD="25.0417.6"

if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(find "$ROOT_DIR" -maxdepth 1 -type d -name 'BookGet GUI*.app' | head -n 1)"
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "app not found under: $ROOT_DIR" >&2
  exit 1
fi
# Paths inside the bundle must follow the APP_PATH actually found above.
APP_BIN="$APP_PATH/Contents/MacOS/BookGetGUILauncher"
HELPER_BIN="$APP_PATH/Contents/Resources/bin/bookget-web-login"
WRAPPER_BIN="$APP_PATH/Contents/Resources/bin/bookget"
HELP_DST="$APP_PATH/Contents/Resources/BookGetGUIHelp.md"
SITES_DST="$APP_PATH/Contents/Resources/sites.json"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
mkdir -p "${APP_BIN:h}" "${HELPER_BIN:h}"
if [[ ! -f "$GUI_SRC" ]]; then
  echo "gui source not found: $GUI_SRC" >&2
  exit 1
fi
if [[ ! -f "$HELPER_SRC" ]]; then
  echo "helper source not found: $HELPER_SRC" >&2
  exit 1
fi
if [[ ! -f "$SITES_SRC" ]]; then
  echo "sites.json not found: $SITES_SRC" >&2
  exit 1
fi

mkdir -p /tmp/clang-module-cache-bookget-gui /tmp/swift-module-cache-bookget-gui
export CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache-bookget-gui
export SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache-bookget-gui

# Back up the previous binaries outside the bundle (they used to pile up
# inside Contents/, bloating the app and getting signed with it). Keep 3.
ts="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT_DIR/build-backups"
mkdir -p "$BACKUP_DIR"
for f in "$APP_BIN" "$HELPER_BIN"; do
  [[ -f "$f" ]] && cp "$f" "$BACKUP_DIR/${f:t}.$ts"
done
# Move legacy in-bundle backups out of the app.
for f in "${APP_BIN:h}"/*.bak.*(N) "${HELPER_BIN:h}"/*.bak.*(N); do
  mv "$f" "$BACKUP_DIR/"
done
for name in BookGetGUILauncher bookget-web-login; do
  old=("$BACKUP_DIR"/$name.*(N.om))  # newest first
  (( ${#old} > 3 )) && rm -f -- "${old[@]:3}"
done

echo "[build] compile launcher..."
swiftc -parse-as-library \
  -module-cache-path /tmp/clang-module-cache-bookget-gui \
  -target "$TARGET" \
  -o "$APP_BIN" \
  "$GUI_SRC"
chmod +x "$APP_BIN"

echo "[build] compile web-login helper..."
swiftc \
  -module-cache-path /tmp/clang-module-cache-bookget-gui \
  -target "$TARGET" \
  -o "$HELPER_BIN" \
  "$HELPER_SRC"
chmod +x "$HELPER_BIN"

if [[ -f "$WRAPPER_SRC" ]]; then
  echo "[build] sync wrapper script..."
  cp "$WRAPPER_SRC" "$WRAPPER_BIN"
  chmod +x "$WRAPPER_BIN"
fi

if [[ -f "$HELP_SRC" ]]; then
  cp "$HELP_SRC" "$HELP_DST"
fi

echo "[build] copy sites.json..."
cp "$SITES_SRC" "$SITES_DST"

if [[ -f "$PLIST_PATH" ]]; then
  /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$PLIST_PATH" >/dev/null 2>&1 || true
  # Keep the bundle identifier as is: UserDefaults (settings, history) and the
  # wrapper's defaults lookups are keyed by it.
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$PLIST_PATH" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$PLIST_PATH" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :NSHumanReadableCopyright 基于 bookget（AGPL-3.0）" "$PLIST_PATH" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string 基于 bookget（AGPL-3.0）" "$PLIST_PATH" >/dev/null 2>&1 || true
fi

echo "[build] ad-hoc codesign..."
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "[done] rebuilt app:"
echo "  $APP_PATH"
