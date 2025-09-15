function lf_RunCameraLocal(sceneID, Nframes)
% Download → process → delete for i=01..10, all inside MATLAB.

  % --- CONFIG ---
  LOCAL_DIR   = fullfile(isethdrsensorRootPath, 'data', sceneID);

  % Ensure local output dir exists
  if ~exist(LOCAL_DIR, 'dir'); mkdir(LOCAL_DIR); end

  for k = 1:Nframes
    i = sprintf('%02d', k);
    fprintf('=== Processing frame %s ===\n', i);
    lf_CameraSim(sceneID, i);
    fprintf('Processed %s\n', i);
  end

  fprintf('All frames processed.\n');
  
end