#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(realpath "$0")")"
DEVELOPER="${DEVELOPER_DIR:-$(xcode-select -p)}"
SDK="$DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
TOOL="$DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin"
APP="${WATTLITE_APP:-$ROOT/build/WattLite.app}"
mkdir -p "$ROOT/build"
# ponytail: 编译和签名都离开 iCloud 目录做。Desktop 下的 fileprovider 会在几秒内给 bundle 补挂
# FinderInfo / fpfs#P，codesign 视其为 detritus 直接拒签（xattr -cr 清得掉，但马上又被加回来），
# 所以在临时目录签好封死，再拷回 build/ 供本机运行。
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BUNDLE="$WORK/WattLite.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
"$TOOL/clang" -isysroot "$SDK" -mmacosx-version-min=14.0 -O2 -Wall -Wextra -c "$ROOT/Sources/SMC.c" -o "$ROOT/build/SMC.o"
FLAGS=(-parse-as-library -swift-version 5 -sdk "$SDK" -target arm64-apple-macosx14.0 -import-objc-header "$ROOT/Sources/SMC.h")
"$TOOL/swiftc" "${FLAGS[@]}" "$ROOT/Sources/Strings.swift" "$ROOT/Sources/PowerReading.swift" "$ROOT/Sources/MacModels.swift" "$ROOT/Tests/Checks.swift" "$ROOT/build/SMC.o" -framework IOKit -o "$ROOT/build/checks"
"$ROOT/build/checks"
"$TOOL/swiftc" "${FLAGS[@]}" -O -whole-module-optimization "$ROOT"/Sources/*.swift "$ROOT/build/SMC.o" -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement -o "$BUNDLE/Contents/MacOS/WattLite"
cp "$ROOT/Info.plist" "$BUNDLE/Contents/Info.plist"
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
cp "$ROOT/build/AppIcon.icns" "$BUNDLE/Contents/Resources/"
if compgen -G "$ROOT/Assets/Adapters/*.png" >/dev/null; then
    mkdir -p "$BUNDLE/Contents/Resources/Adapters"
    cp "$ROOT"/Assets/Adapters/*.png "$BUNDLE/Contents/Resources/Adapters/"
fi
codesign --force --sign - "$BUNDLE"
codesign --verify --strict "$BUNDLE"
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
cp -R "$BUNDLE" "$APP"
printf 'Built %s\n' "$APP"

# bash build.sh release → build/WattLite-<版本>.{zip,dmg}，版本号只从 bundle 里取
if [[ "${1:-}" == "release" ]]; then
    version="$(plutil -extract CFBundleShortVersionString raw "$BUNDLE/Contents/Info.plist")"
    ln -s /Applications "$WORK/Applications"
    ditto -c -k --keepParent "$BUNDLE" "$ROOT/build/WattLite-$version.zip"
    hdiutil create -quiet -volname WattLite -srcfolder "$WORK" -ov -format UDZO "$ROOT/build/WattLite-$version.dmg"
    hdiutil attach -readonly -nobrowse "$ROOT/build/WattLite-$version.dmg" >/dev/null
    codesign --verify --strict /Volumes/WattLite/WattLite.app
    printf 'dmg: %s (版本 %s)\n' "$ROOT/build/WattLite-$version.dmg" "$(plutil -extract CFBundleShortVersionString raw /Volumes/WattLite/WattLite.app/Contents/Info.plist)"
    hdiutil detach -quiet /Volumes/WattLite
    ls -lh "$ROOT/build/WattLite-$version.zip" "$ROOT/build/WattLite-$version.dmg"
fi
