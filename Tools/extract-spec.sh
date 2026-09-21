#!/bin/sh
# Pulls the OpenAPI spec embedded in developer.plex.tv's Redoc page and
# writes it (minified) to DevTools/Resources/plex-openapi.json.
set -eu

cd "$(dirname "$0")/.."
out="DevTools/Resources/plex-openapi.json"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -sSL https://developer.plex.tv/pms/ \
  | sed -n 's/.*__redoc_state = \(.*\)/\1/p' \
  | sed 's/;<\/script>.*$//; s/;$//' \
  | jq -c '.spec.data' > "$tmp"

version="$(jq -r '.info.version | gsub("\n"; "")' "$tmp")"
paths="$(jq '.paths | length' "$tmp")"
mv "$tmp" "$out"
echo "wrote $out — API v$version, $paths paths"
