% lf_RunCamera.m: Pre-render light control (Option A)
% 
% Run camera simulation for each frame iteratively. 
% lf_CameraSim is called for each frame.
% 
% Pre-render light control:
% - assumes light intensities have been modulated in scene
%   before rendering. 
% - no temporal profile is applied here.
% - fixed weights are used for all frames.
% 
% Authored by Ayush Jamdar, 2025

function lf_RunCamera(sceneID, Nframes)
  % --- CONFIG ---
  LOCAL_DIR   = fullfile(isethdrsensorRootPath, 'data', sceneID);

  % Ensure local output dir exists
  if ~exist(LOCAL_DIR, 'dir'); mkdir(LOCAL_DIR); end

  wgts = [3.0114    0.09    0.0498    10];
  % headlight, street light, other, sky light

  for k = 1:Nframes
    i = sprintf('%02d', k);
    fprintf('=== Processing frame %s ===\n', i);
    lf_CameraSim(sceneID, i, wgts, wgts);
    fprintf('Processed %s\n', i);
  end

  fprintf('All frames processed.\n');
  
end