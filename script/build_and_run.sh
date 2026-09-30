#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
SIGNING_IDENTITY="$(cat "$ROOT_DIR/config/signing-identity.txt")"
if [[ ! "$SIGNING_IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
  echo "本地开发签名配置无效。" >&2
  exit 2
fi
if [[ "$MODE" == "run" || "$MODE" == "--verify" ]]; then
  if APP_PIDS="$(pgrep -f "^$ROOT_DIR/dist/Ashot.app/Contents/MacOS/Ashot$")"; then
    kill -TERM $APP_PIDS
  fi
fi
swift build
BIN_DIR="$(swift build --show-bin-path)"
BUILD_ID="$( { rg --files Sources/Ashot Sources/AshotCore | sort | while IFS= read -r source; do shasum -a 256 "$source"; done; shasum -a 256 Package.swift; } | shasum -a 256 | cut -c1-16)"
for APP_NAME in Ashot AshotFixture; do
  BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
  mkdir -p "$BUNDLE/Contents/MacOS"
  cp "$BIN_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
  cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>com.oohevt.$APP_NAME</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>AshotBuildID</key><string>$BUILD_ID</string>
<key>AshotWorkspaceRoot</key><string>$ROOT_DIR</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$BUNDLE"
done
# 开机自启的登录项指向 /Applications/Ashot.app，构建后保持该副本同步；
# 有实例在跑时跳过，避免换掉正在使用的应用包。
if ! pgrep -x Ashot >/dev/null 2>&1; then
  ditto "$ROOT_DIR/dist/Ashot.app" "/Applications/Ashot.app"
fi
case "$MODE" in
  --build-only) ;;
  --new-instance) /usr/bin/open -n "$ROOT_DIR/dist/Ashot.app" ;;
  run) /usr/bin/open -n "$ROOT_DIR/dist/Ashot.app" ;;
  --verify) /usr/bin/open -n "$ROOT_DIR/dist/Ashot.app"; pgrep -x Ashot ;;
  *) echo "usage: $0 [--build-only|--new-instance|run|--verify]" >&2; exit 2 ;;
esac
