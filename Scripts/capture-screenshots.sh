#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/docs/images}"
build_dir="${RIPPLE_BUILD_DIR:-$project_dir/.build/ripple-screenshots}"
mkdir -p "$build_dir" "$output_dir"
source_files=()
for source_path in "$project_dir"/Sources/Ripple/*.swift; do
    if [ "$(basename "$source_path")" != "App.swift" ]; then
        source_files+=("$source_path")
    fi
done
xcrun swiftc -swift-version 5 -module-name RippleScreenshots "${source_files[@]}" \
    "$project_dir/Scripts/CaptureScreenshots.swift" -o "$build_dir/RippleScreenshots"
"$build_dir/RippleScreenshots" "$output_dir" "$build_dir"
xcrun swift "$project_dir/Scripts/MakeIcon.swift" "$build_dir/Docs.iconset"
cp "$build_dir/Docs.iconset/icon_128x128@2x.png" "$output_dir/icon.png"
