#!/bin/bash
# Builds AgentsUsage.app (menu bar only, no Dock icon) from AgentsUsageApp.swift.
# Needs the Xcode command line tools and macOS 13 or later.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "找不到 swiftc。請先執行:xcode-select --install" >&2
  exit 1
fi

APP="AgentsUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  AgentsUsageApp.swift \
  -o "$APP/Contents/MacOS/AgentsUsage"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agents Usage</string>
  <key>CFBundleDisplayName</key><string>Agents Usage</string>
  <key>CFBundleIdentifier</key><string>local.claude-usage-menubar</string>
  <key>CFBundleExecutable</key><string>AgentsUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will run the locally built app.
codesign --force --sign - "$APP"

echo "完成:$(pwd)/$APP"
echo "執行:open \"$(pwd)/$APP\""
