#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BrowserOpeningRouter"
DISPLAY_NAME="Browser Opening Router"
BUNDLE_ID="io.github.choism4.browser-opening-router"
APP_DIR="${1:-/Applications}"
DEST="${APP_DIR}/${APP_NAME}.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

STAGE="$(mktemp -d "${APP_DIR}/.${APP_NAME}.XXXXXX")"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

BUNDLE="${STAGE}/${APP_NAME}.app"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

if [ -f "${REPO_ROOT}/Resources/AppIcon.icns" ]; then
  cp "${REPO_ROOT}/Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

/usr/bin/swiftc -O -target "${TARGET}" -framework AppKit -framework SwiftUI \
  "${REPO_ROOT}/Sources/main.swift" \
  -o "${BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>HTML Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.html</string>
                <string>public.xhtml</string>
            </array>
        </dict>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleURLName</key>
            <string>Web site URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>http</string>
                <string>https</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "${BUNDLE}" >/dev/null 2>&1

rm -rf "${DEST}"
mv "${BUNDLE}" "${DEST}"
"${LSREGISTER}" -f "${DEST}"

echo "Installed: ${DEST}"
echo "Config:    ~/.config/browser-opening-router/config.json"
echo "Next:      System Settings -> Desktop & Dock -> Default web browser -> ${DISPLAY_NAME}"
