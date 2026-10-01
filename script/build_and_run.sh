#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
# --release：优化构建，不注入 AshotBuildID / AshotWorkspaceRoot（否则运行时会把日志写进本工程目录），
# 成品放 dist/release/，并复制一份到桌面 Ashot-<MMDD-HHMM>.app（桌面只保留最新一份）。
CONFIG=debug
OUT="$ROOT_DIR/dist"
APPS=(Ashot AshotFixture)
if [[ "$MODE" == "--release" ]]; then
  CONFIG=release
  OUT="$ROOT_DIR/dist/release"
  APPS=(Ashot)
fi
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
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BUILD_ID="$( { rg --files Sources/Ashot Sources/AshotCore | sort | while IFS= read -r source; do shasum -a 256 "$source"; done; shasum -a 256 Package.swift; } | shasum -a 256 | cut -c1-16)"
for APP_NAME in "${APPS[@]}"; do
  BUNDLE="$OUT/$APP_NAME.app"
  if [[ "$CONFIG" == "release" ]]; then DEV_KEYS=""; else
    DEV_KEYS="<key>AshotBuildID</key><string>$BUILD_ID</string>
<key>AshotWorkspaceRoot</key><string>$ROOT_DIR</string>"
  fi
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
$DEV_KEYS
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$BUNDLE"
done
# 开机自启的登录项指向 /Applications/Ashot.app，构建后保持该副本同步；
# 有实例在跑时跳过，避免换掉正在使用的应用包。
if [[ "$CONFIG" == "debug" ]] && ! pgrep -x Ashot >/dev/null 2>&1; then
  ditto "$ROOT_DIR/dist/Ashot.app" "/Applications/Ashot.app"
fi
case "$MODE" in
  --build-only) ;;
  --new-instance) /usr/bin/open -n "$ROOT_DIR/dist/Ashot.app" ;;
  run) /usr/bin/open -n "$ROOT_DIR/dist/Ashot.app" ;;
  --verify) /usr/bin/open -n "$ROOT_DIR/dist/Ashot.app"; pgrep -x Ashot ;;
  --release)
    codesign --verify --strict "$OUT/Ashot.app"
    if /usr/libexec/PlistBuddy -c "Print :AshotWorkspaceRoot" "$OUT/Ashot.app/Contents/Info.plist" >/dev/null 2>&1; then
      echo "发布包仍含开发注入键，拒绝交付。" >&2; exit 1
    fi
    # 只删桌面上本脚本命名规则的旧副本，不碰其他文件。
    for old in "$HOME"/Desktop/Ashot-[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9].app; do
      if [[ -e "$old" ]]; then rm -rf "$old"; fi
    done
    DESKTOP_COPY="$HOME/Desktop/Ashot-$(date +%m%d-%H%M).app"
    ditto "$OUT/Ashot.app" "$DESKTOP_COPY"
    echo "已交付：$DESKTOP_COPY" ;;
  *) echo "usage: $0 [--build-only|--new-instance|run|--verify|--release]" >&2; exit 2 ;;
esac
