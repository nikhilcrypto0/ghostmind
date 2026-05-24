#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP="/Applications/GhostMind.app"

echo ""
echo "  GhostMind — Installer"
echo "  ────────────────────────────────────"
echo ""

# Build
echo "  Building..."
swift build -c release 2>&1 | grep -E "Build complete|error:|warning:" || true
echo ""

# Kill existing instance
pkill -x ClueyMac 2>/dev/null || true
sleep 0.3

# Create app bundle structure
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy binary, Info.plist, icon
cp .build/release/ClueyMac "$APP/Contents/MacOS/ClueyMac"
cp Info.plist               "$APP/Contents/Info.plist"
cp AppIcon.icns             "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

# Sign
codesign --force --sign - "$APP" 2>/dev/null
echo "  ✓ Signed"
echo "  ✓ Installed to $APP"

echo ""
echo "  ────────────────────────────────────"
echo "  Done. Launching GhostMind..."
echo ""
echo "  On first launch:"
echo "  • Enter your Anthropic + Deepgram API keys"
echo "  • Enable 'Launch at Login' in the settings"
echo "  • Use ⌘⇧Space to show/hide the overlay"
echo ""

open "$APP"
