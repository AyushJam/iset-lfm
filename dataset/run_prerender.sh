# Usage: ./run_camera_prerender.sh <sceneID> <Nframes>
# For a scene in iset3d-tiny/data/scenes/<sceneID>/, 
# run the pre-render (Option A) steps and then render. 
# 
# Run from the iset-lfm/ directory, file might be moved to dataset/.
# 
# Steps:
# 	1. lf_EachLight_DualExposure(<sceneID>, <Nframes>) (control motion and lights)
# 	2. ./render_splitpixel.sh <sceneID> <Nframes>
# 
# Logs are streamed to the terminal and saved to ~/iset/logs.

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
LOG_FILE="${LOG_DIR}/${sceneID}_N${Nframes}_camera_pipeline_${timestamp}.log"

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


# ---- 1) MATLAB: lf_EachLight_DualExposure ----
run_and_log "~/matlab/R2024b/bin/matlab -nodisplay -nosplash -batch \"try; \
	addpath(genpath('~/iset/')); \
	fprintf('Starting lf_EachLight_DualExposure(%s, %d)\\n', '${sceneID}', ${Nframes}); \
	ieInit; \
	lf_EachLight_DualExposure('${sceneID}', ${Nframes}); \
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


# # ---- 3) MATLAB: Run Camera Simulation ----
# DO NOT RUN: Camera simulation requires Matlab UI for image processing. 
# run_and_log "~/matlab/R2024b/bin/matlab -nodisplay -nosplash -batch \"try; \
# 	addpath(genpath('~/iset/')); \
# 	fprintf('Starting lf_RunCamera(%s, %d)\\n', '${sceneID}', ${Nframes}); \
# 	ieInit; \
# 	lf_RunCamera('${sceneID}', ${Nframes}); \
# 	catch e; disp(getReport(e,'extended')); exit(1); end\""


echo | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
echo "CameraSim pipeline COMPLETE for ${sceneID} (N=${Nframes}) - $(date)" | tee -a "$LOG_FILE"
echo "Logs saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
