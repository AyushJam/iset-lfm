#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
REMOTE="amj18@orange.stanford.edu"
REMOTE_BASE="/home/amj18/ISETRemoteRender"
VARIANTS=(skymap otherlights streetlights headlights)

LOCAL_DIR="data/1112153442"
mkdir -p "$LOCAL_DIR"

# Loop i = 01..10
for i in $(seq -w 01 10); do
  echo "=== Processing frame $i ==="

  # 1) Download one set of files (renaming as you want)
  for v in "${VARIANTS[@]}"; do
    SRC="$REMOTE:$REMOTE_BASE/1112153442_${v}/renderings/${i}.exr"
    DST="${LOCAL_DIR}/1112153442_${v}_${i}.exr"
    echo "Downloading: $SRC -> $DST"
    scp "$SRC" "$DST"
  done

  # 2) Run MATLAB with command-line arg i
  # Prefer -batch if available (R2019a+). Falls back to -nodisplay trick if needed.
  if command -v matlab >/dev/null 2>&1; then
    if matlab -help 2>/dev/null | grep -q -- "-batch"; then
      # Clean one-liner: errors cause nonzero exit automatically
      matlab -batch "test_camera('${i}')"
    else
      # Older MATLAB: make sure we exit nonzero on error
      matlab -nodisplay -nosplash -r "try, test_camera('${i}'); catch ME, disp(getReport(ME)); exit(1); end; exit(0);"
    fi
  else
    echo "ERROR: 'matlab' not found on PATH." >&2
    exit 1
  fi

  # 3) Delete the downloaded EXRs
  echo "Cleaning up EXRs for $i"
  rm -f "${LOCAL_DIR}/1112153442_"*"_${i}.exr"

  echo "=== Done $i ==="
done

echo "All frames processed."

