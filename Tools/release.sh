#!/bin/sh
# Builds a Developer ID-signed, notarized, stapled "Dev Tools for Plex.app", packs
# it in a signed, notarized, stapled DMG (build/release/DevToolsForPlex-<version>.dmg),
# publishes it to the landing page as site/DevToolsForPlex-<version>.dmg (the stable
# /DevToolsForPlex.dmg link redirects to it through site/vercel.json, and the version
# line in site/index.html names it), and tags the commit it
# was built from v<version>. The tag's notes are the merges since the last tag
# that changed the app (DevTools/): the repo also holds the site, skills, and
# docs, and the site commit for a release always lands after its tag.
# The name and tag come from MARKETING_VERSION, so bump it for every release;
# the build refuses to start if that tag exists or the tree has changes, since
# the tag has to name exactly what was built.
#
# One-time setup: xcrun notarytool store-credentials notary
# (Apple ID, team LQ2SFRWR75, and an app-specific password from
# appleid.apple.com). NOTARY_PROFILE picks a different keychain profile;
# SKIP_NOTARIZE=1 stops before notarizing, for checking the build locally,
# and leaves site/ and the tags untouched so an unnotarized DMG can't be
# deployed or tagged.
set -eu

cd "$(dirname "$0")/.."
out="build/release"
archive="$out/DevTools.xcarchive"
name="Dev Tools for Plex"
app="$out/export/$name.app"
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

version="$(grep -m1 -oE 'MARKETING_VERSION = [^;]+' DevTools.xcodeproj/project.pbxproj | cut -d' ' -f3)"
tag="v$version"
if [ "$skip" != 1 ]; then
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "$tag is already tagged. Bump MARKETING_VERSION for a new release." >&2
    exit 1
  fi
  if ! git diff --quiet HEAD --; then
    echo "The tree has uncommitted changes; commit them so $tag names what's built." >&2
    exit 1
  fi
fi

rm -rf "$out"
mkdir -p "$out"

xcodebuild -project DevTools.xcodeproj -scheme DevTools \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  -allowProvisioningUpdates -quiet archive

xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
  -exportOptionsPlist Tools/ExportOptions-macOS.plist -allowProvisioningUpdates -quiet

build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")"
dmg="$out/DevToolsForPlex-$version.dmg"

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
ditto "$app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "$name" -srcfolder "$stage" -format UDZO -ov "$dmg" -quiet
rm -rf "$stage"
codesign --sign "$identity" --timestamp "$dmg"

if [ "$skip" = 1 ]; then
  echo "signed, not notarized: $dmg ($version, build $build)"
  exit 0
fi

xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

rm -f site/DevTools*.dmg
cp "$dmg" "site/DevToolsForPlex-$version.dmg"
sed -i '' -E "s|(<p class=\"version\">Version )[^<]*|\1$version|" site/index.html
# Temporary (307), so a browser that followed it doesn't keep the old file's address.
cat > site/vercel.json <<EOF
{
  "redirects": [
    { "source": "/DevToolsForPlex.dmg", "destination": "/DevToolsForPlex-$version.dmg", "permanent": false }
  ]
}
EOF

previous="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$previous" ]; then
  notes="$(git log --first-parent --format='- %s' "$previous"..HEAD -- DevTools | sed 's/^- Merge: /- /' | awk '{ print "- " toupper(substr($0, 3, 1)) substr($0, 4) }')"
else
  notes="- First release"
fi
git tag -a "$tag" -m "Dev Tools for Plex $version (build $build)" -m "$notes"

echo "wrote $dmg ($version, build $build), published it to site/, and tagged $tag:"
echo "$notes"
echo "Next: merge site/index.html and site/vercel.json through a pull request, deploy site/, and git push origin $tag."
