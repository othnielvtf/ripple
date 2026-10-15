#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${RIPPLE_BUILD_DIR:-$project_dir/.build/ripple-tests}"
mkdir -p "$build_dir"
xcrun swiftc -swift-version 5 -module-name RippleTests \
    "$project_dir/Sources/Ripple/PlaybackController.swift" \
    "$project_dir/Tests/PlaybackTests.swift" -o "$build_dir/RippleTests"
"$build_dir/RippleTests" "$@"
xcrun swiftc -swift-version 5 -module-name RippleSettingsTests \
    "$project_dir/Sources/Ripple/PlaybackController.swift" \
    "$project_dir/Sources/Ripple/Appearance.swift" \
    "$project_dir/Sources/Ripple/FileAssociations.swift" \
    "$project_dir/Tests/SettingsTests.swift" -o "$build_dir/RippleSettingsTests"
"$build_dir/RippleSettingsTests"
xcrun swiftc -swift-version 5 -module-name RippleSliderTests \
    "$project_dir/Sources/Ripple/Appearance.swift" \
    "$project_dir/Sources/Ripple/EffectSlider.swift" \
    "$project_dir/Tests/SliderTests.swift" -o "$build_dir/RippleSliderTests"
"$build_dir/RippleSliderTests"
