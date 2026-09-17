#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(realpath "$0")")"
DEVELOPER="${DEVELOPER_DIR:-$(xcode-select -p)}"
SDK="$DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
TOOL="$DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin"
APP="${WATTLITE_APP:-$ROOT/build/WattLite.app}"
mkdir -p "$ROOT/build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
"$TOOL/clang" -isysroot "$SDK" -mmacosx-version-min=14.0 -O2 -Wall -Wextra -c "$ROOT/Sources/SMC.c" -o "$ROOT/build/SMC.o"
FLAGS=(-parse-as-library -swift-version 5 -sdk "$SDK" -target arm64-apple-macosx14.0 -import-objc-header "$ROOT/Sources/SMC.h")
"$TOOL/swiftc" "${FLAGS[@]}" "$ROOT/Sources/PowerReading.swift" "$ROOT/Tests/Checks.swift" "$ROOT/build/SMC.o" -framework IOKit -o "$ROOT/build/checks"
"$ROOT/build/checks"
"$TOOL/swiftc" "${FLAGS[@]}" -O -whole-module-optimization "$ROOT"/Sources/*.swift "$ROOT/build/SMC.o" -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement -o "$APP/Contents/MacOS/WattLite"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ ! -f "$ROOT/build/AppIcon.icns" ]]; then
    "$TOOL/swiftc" -sdk "$SDK" "$ROOT/Tests/MakeIcon.swift" -o "$ROOT/build/make-icon"
    "$ROOT/build/make-icon" "$ROOT/build/icon.png"
    mkdir -p "$ROOT/build/AppIcon.iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ROOT/build/icon.png" --out "$ROOT/build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$ROOT/build/icon.png" --out "$ROOT/build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/"
if compgen -G "$ROOT/Assets/Adapters/*.png" >/dev/null; then
    mkdir -p "$APP/Contents/Resources/Adapters"
    cp "$ROOT"/Assets/Adapters/*.png "$APP/Contents/Resources/Adapters/"
fi
python3 - "$APP" <<'PY'
import os, subprocess, sys
for root, dirs, files in os.walk(sys.argv[1]):
    for path in [root] + [os.path.join(root, name) for name in files]:
        attributes = subprocess.check_output(['/usr/bin/xattr', path], text=True).splitlines()
        for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
            if attribute in attributes:
                subprocess.run(['/usr/bin/xattr', '-d', attribute, path], check=True)
PY
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
