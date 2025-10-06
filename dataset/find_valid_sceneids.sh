#!/usr/bin/env bash
# find_valid_sceneids.sh
# Usage:
#   ./find_valid_sceneids.sh [SCENE_RECIPES_DIR] [OUTPUT_FILE]
# Defaults:
#   SCENE_RECIPES_DIR=/acorn/data/iset/isetauto/Ford/SceneRecipes
#   OUTPUT_FILE=valid_sceneIDs.txt

set -euo pipefail

SCENE_RECIPES_DIR="${1:-/acorn/data/iset/isetauto/Ford/SceneRecipes}"
OUTPUT_FILE="${2:-valid_sceneIDs.txt}"

LGs=(headlights otherlights streetlights skymap)

# Empty/initialize output file
: > "$OUTPUT_FILE"

# In case there are no matches, don't literally loop "*.mat"
shopt -s nullglob

# Use *.mat as the canonical list of sceneIDs
for mat in "$SCENE_RECIPES_DIR"/*.mat; do
  base="$(basename "$mat")"
  sceneID="${base%.mat}"

  valid=1
  # Check the 12 PBRT files: for each LG, we need:
  #   sceneID_{LG}.pbrt
  #   sceneID_{LG}_geometry.pbrt
  #   sceneID_{LG}_materials.pbrt
  for lg in "${LGs[@]}"; do
    for suffix in "" "_geometry" "_materials"; do
      f="$SCENE_RECIPES_DIR/${sceneID}_${lg}${suffix}.pbrt"
      if [[ ! -f "$f" ]]; then
        valid=0
        # Uncomment next line to see what's missing:
        # echo "Missing: $f" >&2
        break 2
      fi
    done
  done

  # The .mat file itself exists by construction (we’re looping over it)
  if [[ $valid -eq 1 ]]; then
    echo "$sceneID" >> "$OUTPUT_FILE"
  fi
done

# Deduplicate & sort (just in case)
sort -u -o "$OUTPUT_FILE" "$OUTPUT_FILE"

echo "Found $(wc -l < "$OUTPUT_FILE") valid sceneIDs."
echo "Saved to: $OUTPUT_FILE"
