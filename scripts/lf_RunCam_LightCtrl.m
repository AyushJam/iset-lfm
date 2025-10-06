% lf_RunCamera.m
% 
% Run camera simulation for each frame iteratively. 
% lf_CameraSim is called for each frame.
% 
% Post-render light control: 
% - apply a temporal profile to each LED light group per frame
% 
% Hyperparameters (can be changed in the code):
% DUTY_MIN: minimum duty cycle
% DUTY_MAX: reduced to get noticable light flicker
% FPWM_MIN: minimum PWM frequency in Hz
% FPWM_MAX: maximum PWM frequency in Hz
% 
% Authored by Ayush Jamdar, 2025

function lf_RunCamera(sceneID, Nframes)
  % --- CONFIG ---
  LOCAL_DIR   = fullfile(isethdrsensorRootPath, 'data', sceneID);

  % Ensure local output dir exists
  if ~exist(LOCAL_DIR, 'dir'); mkdir(LOCAL_DIR); end

  % Light control parameters
  DUTY_MIN = 0.1; % minimum duty cycle
  DUTY_MAX = 0.4; % reduced to get noticable light flicker
  FPWM_MIN = 90; % minimum PWM frequency in Hz
  FPWM_MAX = 120;
  rng(12); % seed for randomness

  % Get random LED parameters for each LED light group
  % 1/2: Headlights
  duty_head = (DUTY_MAX-DUTY_MIN)*rand(1,1) + DUTY_MIN;
  fpwm_head = (FPWM_MAX-FPWM_MIN)*rand(1,1) + FPWM_MIN;
  tp_head = 1000/fpwm_head; % period in msec
  ts_head = tp * rand; % random start time in msec
  A = 1; % amplitude
  offset = 0; % amplitude offset

  % 2/2: Other lights
  duty_other = (DUTY_MAX-DUTY_MIN)*rand(1,1) + DUTY_MIN;
  fpwm_other = (FPWM_MAX-FPWM_MIN)*rand(1,1) + FPWM_MIN;
  tp_other = 1000/fpwm_other; % period in msec
  ts_other = tp * rand; % random start time in msec

  % Load exposure times from metadata
  meta_file = fullfile(piRootPath, 'data', 'scenes', sceneID, ...
        sprintf('%s_lf.mat', sceneID));
  if isfile(meta_file)
      sceneMeta = load(meta_file);
  else
      error('Metadata file not found!');
  end
  te_lpd = sceneMeta.sceneMeta.lpd_exposure; % sec
  te_spd = sceneMeta.sceneMeta.spd_exposure; % sec
  fps = sceneMeta.sceneMeta.fps; % fps

  %% Flicker Model Setup
  % the python module flicker_model.py must be at iset-lfm root
  % and requires numpy
  flickerModulePath = isetlfmRootPath;
  
  if count(py.sys.path, flickerModulePath) == 0
      insert(py.sys.path, int32(0), flickerModulePath);
  end
  
  m = py.importlib.import_module('flicker_model'); 
  py.importlib.reload(m); 
  
  np2mat = @(np) cell2mat(cell(py.numpy.asarray(np).tolist()));
    
  % Generate temporal profiles for each LED light group
  % 1.1: Headlights SPD
  pyout_spd_head = m.phi_over_frames(duty_head, fpwm_head, te_spd*1000, ...
    ts_head, fps, 1, A, offset); % run for 1 second
  time_np_spd_head = pyout_spd_head{1};
  phi_np_spd_head = pyout_spd_head{2};
  time_spd_head = np2mat(time_np_spd_head);
  phi_spd_head = np2mat(phi_np_spd_head);

  % 1.2: Headlights LPD
  pyout_lpd_head = m.phi_over_frames(duty_head, fpwm_head, te_lpd*1000, ...
    ts_head, fps, 1, A, offset); % run for 1 second
  time_np_lpd_head = pyout_lpd_head{1};
  phi_np_lpd_head = pyout_lpd_head{2};
  time_lpd_head = np2mat(time_np_lpd_head);
  phi_lpd_head = np2mat(phi_np_lpd_head);

  % 2.1: Other lights SPD
  pyout_spd_other = m.phi_over_frames(duty_other, fpwm_other, te_spd*1000, ...
    ts_other, fps, 1, A, offset); % run for 1 second
  time_np_spd_other = pyout_spd_other{1};
  phi_np_spd_other = pyout_spd_other{2};
  time_spd_other = np2mat(time_np_spd_other);
  phi_spd_other = np2mat(phi_np_spd_other);

  % 2.2: Other lights LPD
  pyout_lpd_other = m.phi_over_frames(duty_other, fpwm_other, te_lpd*1000, ...
    ts_other, fps, 1, A, offset); % run for 1 second
  time_np_lpd_other = pyout_lpd_other{1};
  phi_np_lpd_other = pyout_lpd_other{2};
  time_lpd_other = np2mat(time_np_lpd_other);
  phi_lpd_other = np2mat(phi_np_lpd_other);

  % Initial light group weights
  wgts = [3.0114    0.09    0.0498    10];
  % headlight, street light, other, sky light
  
  for k = 1:Nframes
    i = sprintf('%02d', k);
    fprintf('=== Processing frame %s ===\n', i);

    % Modulate weights according to temporal profiles
    wgts_mod_spd = wgts;
    wgts_mod_lpd = wgts;
    wgts_mod_spd(1) = wgts(1) * phi_spd_head(k); % headlight
    wgts_mod_spd(3) = wgts(3) * phi_spd_other(k); % other light
    wgts_mod_lpd(1) = wgts(1) * phi_lpd_head(k); % headlight
    wgts_mod_lpd(3) = wgts(3) * phi_lpd_other(k); % other light

    lf_CameraSim(sceneID, i, wgts_mod_spd, wgts_mod_lpd);
    fprintf('Processed %s\n', i);
  end

  fprintf('All frames processed.\n');
  
end