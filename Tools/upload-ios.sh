#!/bin/sh
# Archives the iOS app and uploads it to App Store Connect for TestFlight.
#
# Needs the app record (bundle ID mldgg.devtools) to exist in App Store Connect
# and an Apple ID for team LQ2SFRWR75 signed in under Xcode ▸ Settings ▸
# Accounts; signing and the upload both go through that account. The export
# lets Xcode raise the build number past the last upload, so the project's
# own build number doesn't need bumping for each TestFlight build.
set -eu

cd "$(dirname "$0")/.."
out="build/ios"
archive="$out/DevTools.xcarchive"

rm -rf "$out"
mkdir -p "$out"

xcodebuild -project DevTools.xcodeproj -scheme DevTools \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -allowProvisioningUpdates -quiet archive

xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
  -exportOptionsPlist Tools/ExportOptions-iOS.plist -allowProvisioningUpdates

echo "uploaded; the build shows under TestFlight in App Store Connect once processing finishes"
