% lf_RunCameraRemote.m
% Under development. Not yet part of iset-lfm.
% 
% Ayush Jamdar, 2025

function lf_RunCameraRemote()
% Download → process → delete for i=01..10, all inside MATLAB.

  % --- CONFIG ---
  REMOTE      = 'amj18@orange.stanford.edu';
  REMOTE_BASE = '/home/amj18/ISETRemoteRender';
  SCENE_ID    = '1112153442';
  VARIANTS    = {'skymap','otherlights','streetlights','headlights'};
  LOCAL_DIR   = fullfile(isethdrsensorRootPath, 'data', SCENE_ID);

  % Ensure local output dir exists
  if ~exist(LOCAL_DIR, 'dir'); mkdir(LOCAL_DIR); end

  % Confirm scp exists
  check_scp();

  for k = 1:10
    i = sprintf('%02d', k);
    fprintf('=== Processing frame %s ===\n', i);

    % 1) Download one set of files, renaming locally
    exr_paths = cell(1, numel(VARIANTS));
    for vi = 1:numel(VARIANTS)
      v = VARIANTS{vi};

      remote_file_rel = sprintf('%s/%s_%s/renderings/%s.exr', ...
                                REMOTE_BASE, SCENE_ID, v, i);
      remote_spec     = sprintf('%s:%s', REMOTE, dq(remote_file_rel));
      local_file      = fullfile(LOCAL_DIR, sprintf('%s_%s_%s.exr', SCENE_ID, v, i));

      cmd = sprintf('scp -C %s %s', remote_spec, dq(local_file));  % -C = compression
      [status, out] = system(cmd);
      if status ~= 0
        error('SCP failed for %s\nCommand: %s\nOutput:\n%s', remote_file_rel, cmd, out);
      end
      exr_paths{vi} = local_file;
    end

    % 2) Ensure cleanup even if processing errors
    cleanupObj = onCleanup(@() safeDelete(exr_paths));

    % 3) Run your MATLAB processor (expects test_camera(i) to read those EXRs)
    test_camera(i);
    fprintf('Processed %s\n', i);

    % 4) Delete the downloaded EXRs (cleanupObj would also handle this on error)
    safeDelete(exr_paths);
    clear cleanupObj;  % prevent double deletion message if any
  end

  fprintf('All frames processed.\n Generating video... \n');

  % ---------- helpers ----------
  function check_scp()
    [s,~] = system('command -v scp >/dev/null 2>&1');
    if s ~= 0
      error('`scp` not found on PATH. Install OpenSSH or add it to PATH.');
    end
  end

  % Double-quote a path for the shell (handles spaces)
  function q = dq(p)
    q = ['"', strrep(p, '"', '\"'), '"'];
  end

  function safeDelete(paths)
    for ii = 1:numel(paths)
      if ~isempty(paths{ii}) && exist(paths{ii}, 'file')
        delete(paths{ii});
      end
    end
  end
end
