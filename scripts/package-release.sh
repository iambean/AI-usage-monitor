#!/bin/zsh

set -euo pipefail

project_root=${0:A:h:h}
version=$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$project_root/Resources/Info.plist"
)
signing_identity=${AI_USAGE_SIGNING_IDENTITY:--}
release_name="AI-Usage-$version-universal"

if [[ "$signing_identity" == "-" ]]; then
    release_name="$release_name-adhoc"
fi

app_bundle="$project_root/dist/AI Usage.app"
zip_path="$project_root/dist/$release_name.zip"
dmg_path="$project_root/dist/$release_name.dmg"
staging_directory=$(mktemp -d)

trap 'rm -rf "$staging_directory"' EXIT

"$project_root/scripts/build-app.sh"

rm -f "$zip_path" "$dmg_path"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_path"

ditto "$app_bundle" "$staging_directory/AI Usage.app"
ln -s /Applications "$staging_directory/Applications"
hdiutil create \
    -volname "AI Usage" \
    -srcfolder "$staging_directory" \
    -ov \
    -format UDZO \
    "$dmg_path"

if [[ "$signing_identity" != "-" ]]; then
    codesign \
        --force \
        --timestamp \
        --sign "$signing_identity" \
        "$dmg_path"
fi

echo "$zip_path"
echo "$dmg_path"
