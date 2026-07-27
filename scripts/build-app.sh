#!/bin/zsh

set -euo pipefail

project_root=${0:A:h:h}
app_bundle="$project_root/dist/AI Usage.app"
contents="$app_bundle/Contents"
executable="$project_root/.build/apple/Products/Release/AIUsageMonitor"
collector="$project_root/.build/apple/Products/Release/AIUsageCollector"
icon_source="$project_root/Resources/AppIcon-1024.png"
icon_work=$(mktemp -d)
iconset="$icon_work/AppIcon.iconset"
signing_identity=${AI_USAGE_SIGNING_IDENTITY:--}

trap 'rm -rf "$icon_work"' EXIT

cd "$project_root"
swift build -c release --arch arm64 --arch x86_64 --product AIUsageMonitor
swift build -c release --arch arm64 --arch x86_64 --product AIUsageCollector

if [[ -e "$app_bundle" ]]; then
    rm -rf "$app_bundle"
fi

mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Helpers"
cp "$executable" "$contents/MacOS/AIUsageMonitor"
cp "$collector" "$contents/Helpers/AIUsageCollector"
cp "$project_root/Resources/Info.plist" "$contents/Info.plist"
cp "$project_root/Resources/ProviderIcons/"*.png "$contents/Resources/"

mkdir -p "$iconset"
sips -z 16 16 "$icon_source" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_source" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_source" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset/icon_512x512.png" >/dev/null
cp "$icon_source" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"

if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$contents/Helpers/AIUsageCollector"
    codesign --force --sign - "$app_bundle"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$contents/Helpers/AIUsageCollector"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$app_bundle"
fi

echo "$app_bundle"
