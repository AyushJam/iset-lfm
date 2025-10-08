#!/usr/bin/env bash
# 
# Usage: ./render_save_delete.sh <sceneID> <Nframes>
# Steps:
#   A) ./prepare_scene.sh <sceneID>
#   1) MATLAB: lf_DualExposure(<sceneID>, <Nframes>)
#   2) ./render_splitpixel.sh <sceneID> <Nframes>
#   3) Save to database on /acorn/.../SceneLFM
#
# Logs are streamed to the terminal and saved to ~/iset/iset-lfm/dataset/logs.
# 
# Authored by Ayush Jamdar with AI assistance

set -euo pipefail

if [[ $# -lt 2 ]]; then
	echo "Usage: $0 <sceneID> <Nframes>"
	exit 1
fi

sceneID="$1"
Nframes="$2"

if ! [[ "$Nframes" =~ ^[0-9]+$ ]] || [[ "$Nframes" -le 0 ]]; then
	echo "ERROR: Nframes must be a positive integer. Got: '$Nframes'"
	exit 1	
fi

# ---- Logging ----
LOG_DIR="${HOME}/iset/iset-lfm/dataset/logs"
mkdir -p "$LOG_DIR"
timestamp="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/${sceneID}_N${Nframes}_pipeline_${timestamp}.log"

{
	echo "==============================================="
	echo "Scene pipeline start - $(date)"
	echo "SceneID: ${sceneID}"
	echo "Nframes: ${Nframes}"
	echo "Log file: ${LOG_FILE}"
	echo "Working dir: $(pwd)"
	echo "==============================================="
} | tee -a "$LOG_FILE"

# Helper
run_and_log() {
	local cmd="$1"
	echo
	echo "---- RUN: $cmd ----" | tee -a "$LOG_FILE"
	local start_time=$(date +%s)
	set -o pipefail
	{ bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"; }
	local status=${PIPESTATUS[0]}
	set +o pipefail
	local end_time=$(date +%s)
	local elapsed=$((end_time - start_time))
	printf "---- TIME: %02d:%02d (mm:ss) ----\n" $((elapsed/60)) $((elapsed%60)) | tee -a "$LOG_FILE"
	echo "---- EXIT: $status ----" | tee -a "$LOG_FILE"
	return $status
}


# Safe delete helper (refuses to delete if path doesn't match expected base/sceneID)
safe_delete_dir() {
	local target="$1"
	local expected_base="$2"
	if [[ -z "$target" || -z "$expected_base" ]]; then
		echo "SAFE_RM: missing args" >&2
		return 3
	fi
	# Must start with expected base and contain the sceneID as a path component
	if [[ "$target" == "$expected_base"* ]] && [[ "$target" == *"/$sceneID"* ]] && [[ -d "$target" ]]; then
		rm -rf -- "$target"
		echo "Deleted: $target"
	else
		echo "SAFE_RM: Refusing to delete '$target' (fails base/sceneID/exists checks)."
	fi
}

# ---- A) Prepare scene ----
run_and_log "./prepare_scene.sh \"${sceneID}\""

# ---- 1) MATLAB: lf_DualExposure ----
run_and_log "~/matlab/R2024b/bin/matlab -nodisplay -nosplash -batch \"try; \
	addpath(genpath('~/iset/')); \
	fprintf('Starting lf_DualExposure(%s, %d)\\n', '${sceneID}', ${Nframes}); \
	lf_DualExposure('${sceneID}', ${Nframes}); \
	catch e; disp(getReport(e,'extended')); exit(1); end\""

# ---- 2) Render ----
LOCAL_DIR="${HOME}/iset/iset3d-tiny/local"
if [[ ! -d "$LOCAL_DIR" ]]; then
	echo "ERROR: Local dir not found: $LOCAL_DIR" | tee -a "$LOG_FILE"
	exit 2
fi

pushd "$LOCAL_DIR" > /dev/null
run_and_log "./render_splitpixel.sh $sceneID $Nframes"
popd > /dev/null

# ==== Post-render data movement & cleanup ====

SRC_LOCAL="${HOME}/iset/iset3d-tiny/local"
SRC_DATA="${HOME}/iset/iset3d-tiny/data/scenes"
DEST_ROOT="/acorn/data/iset/isetauto/Ford/SceneLFM"

LGs=(headlights otherlights skymap streetlights)
EXPTS=(spd lpd)

# Choose copy tool: rsync if available (filters *.exr cleanly), else cp fallback
use_rsync=0
if command -v rsync >/dev/null 2>&1; then
	use_rsync=1
fi

# 3.1 Copy rendered EXRs
for LG in "${LGs[@]}"; do
	for x in "${EXPTS[@]}"; do
		SRC_EXR_DIR="${SRC_LOCAL}/${sceneID}_${LG}/${x}/renderings"
		DEST_EXR_DIR="${DEST_ROOT}/${sceneID}/${sceneID}_${LG}/${x}"
		if [[ -d "$SRC_EXR_DIR" ]]; then
			run_and_log "sudo mkdir -p \"$DEST_EXR_DIR\""
			if [[ $use_rsync -eq 1 ]]; then
				run_and_log "sudo rsync -a --prune-empty-dirs --include='*/' --include='*.exr' --exclude='*' \"$SRC_EXR_DIR/\" \"$DEST_EXR_DIR/\""
			else
				# cp fallback: only copy .exr files if any exist
				run_and_log \"bash -c 'shopt -s nullglob; files=(\"$SRC_EXR_DIR\"/*.exr); [[ \${#files[@]} -gt 0 ]] && sudo cp -av \"${SRC_EXR_DIR}\"/*.exr \"${DEST_EXR_DIR}/\" || echo \"No EXRs found in ${SRC_EXR_DIR}\"'\"
			fi
		else
			echo "WARN: Source EXR dir missing: $SRC_EXR_DIR" | tee -a "$LOG_FILE"
		fi
	done
done

# 3.2 Copy metadata (.mat)
SRC_META="${SRC_DATA}/${sceneID}/${sceneID}_lf.mat"
DEST_META_DIR="${DEST_ROOT}/${sceneID}"
if [[ -f "$SRC_META" ]]; then
	run_and_log "sudo mkdir -p \"$DEST_META_DIR\""
	run_and_log "sudo cp -av \"$SRC_META\" \"$DEST_META_DIR/\""
else
	echo "WARN: Metadata file not found: $SRC_META" | tee -a "$LOG_FILE"
fi

# 3.3 Cleanup local data to avoid bloat
# - /home/amj18/iset/iset3d-tiny/data/scenes/sceneID/
# - /home/amj18/iset/iset3d-tiny/local/sceneID_{LG}/
echo "Starting cleanup..." | tee -a "$LOG_FILE"

# Delete data/scenes/sceneID
safe_delete_dir "${SRC_DATA}/${sceneID}" "${SRC_DATA}/"

# Delete local/sceneID_{LG} for all LGs
for LG in "${LGs[@]}"; do
	safe_delete_dir "${SRC_LOCAL}/${sceneID}_${LG}" "${SRC_LOCAL}/"
done

echo | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
echo "Scene pipeline COMPLETE for ${sceneID} (N=${Nframes}) - $(date)" | tee -a "$LOG_FILE"
echo "Logs saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
