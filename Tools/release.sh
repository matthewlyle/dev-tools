#!/bin/sh
# Builds a Developer ID-signed, notarized, stapled DevTools.app and zips it
# for direct distribution: build/release/DevTools-<version>.zip.
#
# One-time setup: xcrun notarytool store-credentials notary
# (Apple ID, team LQ2SFRWR75, and an app-specific password from
# appleid.apple.com). NOTARY_PROFILE picks a different keychain profile;
# SKIP_NOTARIZE=1 stops after signing, for checking the build locally.
set -eu

cd "$(dirname "$0")/.."
out="build/release"
archive="$out/DevTools.xcarchive"
app="$out/export/DevTools.app"
profile="${NOTARY_PROFILE:-notary}"
skip="${SKIP_NOTARIZE:-0}"

if [ "$skip" != 1 ] && ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "No notarytool credentials under \"$profile\". Run: xcrun notarytool store-credentials $profile" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

xcodebuild -project DevTools.xcodeproj -scheme DevTools \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  -allowProvisioningUpdates -quiet archive

xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
  -exportOptionsPlist Tools/ExportOptions.plist -allowProvisioningUpdates -quiet

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")"
zip="$out/DevTools-$version.zip"

codesign --verify --deep --strict "$app"

if [ "$skip" = 1 ]; then
  ditto -c -k --keepParent "$app" "$zip"
  echo "signed, not notarized: $zip ($version, build $build)"
  exit 0
fi

# Notarization takes a zip; the ticket is then stapled to the app itself so
# Gatekeeper can check it offline, which means zipping again afterwards.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
rm "$out/notarize.zip"

ditto -c -k --keepParent "$app" "$zip"
echo "wrote $zip ($version, build $build)"
