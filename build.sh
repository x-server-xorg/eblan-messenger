#!/bin/bash
# Eblan-Messenger Build Script
# Builds all clients

set -e

FLUTTER_BIN="${FLUTTER_HOME:-/home/valance78/flutter}/bin/flutter"

echo "=== Building Eblan-Messenger ==="
echo ""

# 1. Server
echo "--- Server ---"
cd "$(dirname "$0")/server"
npm install
echo "Server deps installed."
echo ""

# 2. Web
echo "--- Web Client ---"
cd "$(dirname "$0")/client"
"$FLUTTER_BIN" build web
echo "Web build: client/build/web/"
echo ""

# 3. Android
echo "--- Android APK ---"
cd "$(dirname "$0")/client"
"$FLUTTER_BIN" build apk --debug
echo "Android APK: client/build/app/outputs/flutter-apk/app-debug.apk"
echo ""

echo "=== Build Complete ==="
echo ""
echo "To build Linux (requires clang++, ninja, pkg-config):"
echo "  cd client && flutter build linux"
echo ""
echo "To build Windows (requires Windows SDK on Windows):"
echo "  cd client && flutter build windows"
