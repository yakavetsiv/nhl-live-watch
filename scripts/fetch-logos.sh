#!/bin/bash
# Downloads the official NHL team logos and turns them into the TeamLogos asset catalog.
# Logos are NHL trademarks, so the catalog is gitignored: run this once before building.
# Without it the app and widget fall back to team abbreviations.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=watch/Shared/TeamLogos.xcassets
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$OUT/Contents.json"

abbrevs=$(curl -sfL https://api-web.nhle.com/v1/standings/now \
  | python3 -I -c 'import json,sys; print(" ".join(r["teamAbbrev"]["default"] for r in json.load(sys.stdin)["standings"]))')

for team in $abbrevs; do
  set_dir="$OUT/logo-$team.imageset"
  mkdir -p "$set_dir"
  curl -sfL "https://assets.nhle.com/logos/nhl/svg/${team}_light.svg" -o "$TMP/$team.svg"
  swift scripts/svg2png.swift "$TMP/$team.svg" "$set_dir/$team.png" 120
  printf '{\n  "images" : [ { "filename" : "%s.png", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' "$team" > "$set_dir/Contents.json"
  echo "  $team"
done
echo "Wrote $(ls -d "$OUT"/*.imageset | wc -l | tr -d ' ') logos to $OUT"
