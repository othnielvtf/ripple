#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/dist}"
build_dir="${RIPPLE_BUILD_DIR:-$project_dir/.build/ripple-release}"
app_path="$output_dir/Ripple.app"
mkdir -p "$build_dir" "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

for architecture in arm64 x86_64; do
    echo "Building ${architecture}…"
    xcrun swiftc -swift-version 5 -O -whole-module-optimization \
        -target "$architecture-apple-macos13.0" -module-name Ripple \
        "$project_dir"/Sources/Ripple/*.swift -o "$build_dir/Ripple-$architecture"
done
xcrun lipo -create "$build_dir/Ripple-arm64" "$build_dir/Ripple-x86_64" -output "$app_path/Contents/MacOS/Ripple"
cp "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
if [ -f "$project_dir/LICENSE" ]; then
    cp "$project_dir/LICENSE" "$app_path/Contents/Resources/LICENSE"
fi
xcrun swift "$project_dir/Scripts/MakeIcon.swift" "$build_dir/Ripple.iconset"
xcrun iconutil -c icns "$build_dir/Ripple.iconset" -o "$app_path/Contents/Resources/Ripple.icns"
/usr/bin/codesign --force --sign - "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"
echo "Built: $app_path"
