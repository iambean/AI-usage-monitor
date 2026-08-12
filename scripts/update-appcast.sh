#!/bin/zsh

set -euo pipefail

project_root=${0:A:h:h}
version=$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$project_root/Resources/Info.plist"
)
build=$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "$project_root/Resources/Info.plist"
)
archive="$project_root/dist/AI-Usage-$version-arm64-adhoc.zip"
appcast=${APPCAST_PATH:-"$project_root/appcast.xml"}
sign_update=$(
    find "$project_root/.build" \
        -path '*/bin/sign_update' \
        -type f \
        -print \
        -quit
)

if [[ ! -s "$archive" ]]; then
    echo "Missing Sparkle update archive: $archive" >&2
    exit 1
fi
if [[ -z "$sign_update" ]]; then
    echo "Sparkle sign_update was not found" >&2
    exit 1
fi
if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
    echo "SPARKLE_EDDSA_PRIVATE_KEY is required" >&2
    exit 1
fi

signature_output=$(
    print -rn -- "$SPARKLE_EDDSA_PRIVATE_KEY" \
        | "$sign_update" --ed-key-file - "$archive"
)
signature=$(
    print -r -- "$signature_output" \
        | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p'
)
archive_length=$(
    wc -c < "$archive" | tr -d '[:space:]'
)

if [[ -z "$signature" || -z "$archive_length" ]]; then
    echo "Sparkle signature metadata could not be parsed" >&2
    exit 1
fi

updated_at=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
download_url="https://github.com/iambean/AI-usage-monitor/releases/download/v$version/AI-Usage-$version-arm64-adhoc.zip"
temporary_appcast=$(mktemp)

awk \
    -v version="$version" \
    -v build="$build" \
    -v updated_at="$updated_at" \
    -v download_url="$download_url" \
    -v archive_length="$archive_length" \
    -v signature="$signature" '
      /<item>/ { in_item = 1 }
      /<\/item>/ { in_item = 0; next }
      in_item { next }
      /<\/channel>/ {
        print "    <item>"
        print "      <title>Version " version "</title>"
        print "      <pubDate>" updated_at "</pubDate>"
        print "      <link>https://github.com/iambean/AI-usage-monitor/releases/tag/v" version "</link>"
        print "      <sparkle:version>" build "</sparkle:version>"
        print "      <sparkle:shortVersionString>" version "</sparkle:shortVersionString>"
        print "      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
        print "      <enclosure"
        print "        url=\"" download_url "\""
        print "        length=\"" archive_length "\""
        print "        type=\"application/octet-stream\""
        print "        sparkle:edSignature=\"" signature "\" />"
        print "    </item>"
      }
      { print }
    ' "$appcast" > "$temporary_appcast"

mv "$temporary_appcast" "$appcast"
echo "$appcast"
