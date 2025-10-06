#!/usr/bin/env bash
# Usage: ./prepare_scene.sh <sceneID>
# Example: ./prepare_scene.sh 1112153442
#
# Copies PBRT files per group and shared assets into the target scene folders.
# 
# Note: shared assets (geometry, skymaps, textures) are symbolic links
#       to a common location that hosts all the data and should not be duplicated.
#       These symlinks must be present in $SCENES_ROOT.
# 
# Update paths as needed:
#   RECIPES_ROOT: where the PBRT scene recipes are stored
#   SCENES_ROOT: where the scene folders will be created
# 
# Authored by Ayush M. Jamdar (September 2025) with AI assistance. 

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <sceneID>"
  exit 1
fi

sceneID="$1"

# Source roots
RECIPES_ROOT="/acorn/data/iset/isetauto/Ford/SceneRecipes"
SCENES_ROOT="$HOME/iset/iset3d-tiny/data/scenes"

# Groups
groups=(skymap headlights otherlights streetlights)

# Ensure base target exists
TARGET_BASE="${SCENES_ROOT}/${sceneID}"
mkdir -p "$TARGET_BASE"

# Make sure source dirs exist
if [[ ! -d "$RECIPES_ROOT" ]]; then
  echo "ERROR: Recipes root not found: $RECIPES_ROOT" >&2
  exit 2
fi
if [[ ! -d "$SCENES_ROOT" ]]; then
  echo "ERROR: Scenes root not found: $SCENES_ROOT" >&2
  exit 2
fi

# Copy these (preserving symlinks) into each group folder
shared_dirs=(geometry skymaps textures)

# Helper: copy with glob safety
copy_glob() {
  local pattern="$1"
  local dest_dir="$2"
  shopt -s nullglob
  local matches=($pattern)
  shopt -u nullglob

  if (( ${#matches[@]} == 0 )); then
    echo "  WARN: No matches for ${pattern}"
    return 0
  fi

  echo "  Copying ${#matches[@]} files -> ${dest_dir}"
  cp -aP "${matches[@]}" "$dest_dir"
}

echo "Preparing scene: ${sceneID}"
echo "Target base: ${TARGET_BASE}"
echo

for g in "${groups[@]}"; do
  echo "== Group: ${g} =="

  # 1) Destination directory for this group
  DEST_DIR="${TARGET_BASE}/${sceneID}_${g}"
  mkdir -p "$DEST_DIR"
  echo "  Created: $DEST_DIR"

  # 2) Copy PBRT recipe files: sceneID_g*.pbrt
  #    from /acorn/.../SceneRecipes/ -> DEST_DIR
  recipe_pattern="${RECIPES_ROOT}/${sceneID}_${g}"*.pbrt
  copy_glob "$recipe_pattern" "$DEST_DIR"

  # 3) Copy shared dirs (preserving symlinks) from scenes root into each group dir
  for d in "${shared_dirs[@]}"; do
    src="${SCENES_ROOT}/${d}"
    if [[ -e "$src" ]]; then
      echo "  Copying shared '${d}' -> ${DEST_DIR}/"
      cp -aP "$src" "$DEST_DIR/"
    else
      echo "  WARN: Shared path missing: $src"
    fi
  done

  echo
done

echo "Done."

