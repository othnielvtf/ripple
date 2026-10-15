#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$project_dir/Resources/Info.plist")"
release_version="${1:-$app_version}"
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Use a numeric version such as 1.2.0." >&2
    exit 1
fi
case "$release_version" in
    "$app_version"|"$app_version.0") ;;
    *) echo "Release version must match the app version ($app_version)." >&2; exit 1 ;;
esac
dist_dir="$project_dir/dist"
"$project_dir/Scripts/build.sh" "$dist_dir"
archive="Ripple-${release_version}-macOS-universal.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$dist_dir/Ripple.app" "$dist_dir/$archive"
(
    cd "$dist_dir"
    /usr/bin/shasum -a 256 "$archive" > SHA256SUMS
    /usr/bin/unzip -tq "$archive"
)
echo "Release archive: $dist_dir/$archive"
