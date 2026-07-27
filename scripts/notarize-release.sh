#!/bin/zsh

set -euo pipefail

if (( $# != 1 )); then
    echo "Usage: AI_USAGE_NOTARY_PROFILE=<profile> $0 <release.dmg>" >&2
    exit 64
fi

dmg_path=$1
notary_profile=${AI_USAGE_NOTARY_PROFILE:-}

if [[ ! -f "$dmg_path" ]]; then
    echo "DMG not found: $dmg_path" >&2
    exit 66
fi

if [[ -z "$notary_profile" ]]; then
    echo "AI_USAGE_NOTARY_PROFILE is required" >&2
    exit 64
fi

xcrun notarytool submit \
    "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl \
    --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "$dmg_path"
