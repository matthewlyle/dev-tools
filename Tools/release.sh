#!/bin/sh
# Builds a Developer ID-signed, notarized, stapled DevTools.app, packs it in a
# signed, notarized, stapled DMG (build/release/DevTools-<version>.dmg), and
# publishes it to the landing page: site/DevTools.dmg plus the version line in
# site/index.html.
#
# One-time setup: xcrun notarytool store-credentials notary
# (Apple ID, team LQ2SFRWR75, and an app-specific password from
# appleid.apple.com). NOTARY_PROFILE picks a different keychain profile;
# SKIP_NOTARIZE=1 stops before notarizing, for checking the build locally,
# and leaves site/ untouched so an unnotarized DMG can't be deployed.
set -eu

cd "$(dirname "$0")/.."
out="build/release"
archive="$out/DevTools.xcarchive"
app="$out/export/DevTools.app"
team="LQ2SFRWR75"
profile="${NOTARY_PROFILE:-notary}"
skip="${SKIP_NOTARIZE:-0}"

if [ "$skip" != 1 ] && ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "No notarytool credentials under \"$profile\". Run: xcrun notarytool store-credentials $profile" >&2
  exit 1
fi

identity="$(security find-identity -v -p codesigning | awk -v team="($team)" '/"Developer ID Application: / && index($0, team) { print $2; exit }')"
if [ -z "$identity" ]; then
  echo "No Developer ID Application certificate for team $team in the keychain." >&2
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
dmg="$out/DevTools-$version.dmg"

codesign --verify --deep --strict "$app"

# The app is notarized and stapled on its own before it goes in the DMG, so it
# still passes Gatekeeper offline once it's been copied out to Applications.
if [ "$skip" != 1 ]; then
  ditto -c -k --keepParent "$app" "$out/notarize.zip"
  xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$profile" --wait
  xcrun stapler staple "$app"
  spctl --assess --type execute --verbose "$app"
  rm "$out/notarize.zip"
fi

stage="$out/dmg"
mkdir "$stage"
ditto "$app" "$stage/DevTools.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Dev Tools for Plex" -srcfolder "$stage" -format UDZO -ov "$dmg" -quiet
rm -rf "$stage"
codesign --sign "$identity" --timestamp "$dmg"

if [ "$skip" = 1 ]; then
  echo "signed, not notarized: $dmg ($version, build $build)"
  exit 0
fi

xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

cp "$dmg" site/DevTools.dmg
sed -i '' -E "s|(<p class=\"version\">Version )[^<]*|\1$version|" site/index.html

echo "wrote $dmg ($version, build $build) and published it to site/"
