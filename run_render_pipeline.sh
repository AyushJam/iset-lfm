# Usage: ./run_render_pipeline.sh <sceneID> <Nframes>
# Steps:
#   A) ./prepare_scene.sh <sceneID>
#   1) MATLAB: lf_DualExposure(<sceneID>, <Nframes>)
#   2) ./render_splitpixel.sh <sceneID> <Nframes>
#
# Logs are streamed to the terminal and saved to ~/iset/logs.
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
LOG_DIR="${HOME}/iset/logs"
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
	set -o pipefail
	{ bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"; } ; local status=${PIPESTATUS[0]}
	set +o pipefail
	echo "---- EXIT: $status ----" | tee -a "$LOG_FILE"
	return $status
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
	echo \"ERROR: Local dir not found: $LOCAL_DIR\" | tee -a \"$LOG_FILE\"
	exit 2
fi

pushd "$LOCAL_DIR" > /dev/null
run_and_log "./render_splitpixel.sh $sceneID $Nframes"
popd > /dev/null

echo | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
echo "Scene pipeline COMPLETE for ${sceneID} (N=${Nframes}) - $(date)" | tee -a "$LOG_FILE"
echo "Logs saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"

