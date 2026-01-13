% lf_DualExposure: Post-render light control version
% 
% Script to create dual-exposure (LPD and SPD) PBRT files
% N frames per light group per scene for a moving camera
% 
% Post-render Light Control (Option B): 
% - [Key Idea] LEDs: all lights in a group (otherlights or headlights)
%   will be controlled together as one single light source AFTER rendering.
% 
%       In other words, all LEDs in a group are in sync.
%       This assumption makes the simulation faster, with an intention 
%       to build a dataset.
% 
% - The light intensity will be modulated frame-by-frame during camera simulation
%   according to the LED flicker model. We don't modulate lights in the PBRT. 
% - We call this "post-render light control".
% - For pre-render light control, see lf_DualExposure_PreRender.m
% 
% Camera Control:
% - Moving camera at a constant speed (hyperparam)
% - Two exposure durations (hyperparam): LPD (short) and SPD (long)
% - Fixed frame rate (hyperparam)
%
% Inputs:
% - sceneID: string, e.g. '1112153442'
% - Nframes: integer, number of frames to write per light group
% 
% Authored by Ayush M. Jamdar (August 2025).
% 

function lf_DualExposure(sceneID, Nframes)
    % DON'T run ieInit here; it will delete input args
    % ieInit; % Run it in cmd win before every session
    CAM_SPEED_MIN = 20; % m/s, empirically tuned, minimum blur required
    CAM_SPEED_MAX = 50; % m/s tuned for maximum blur 
    % this is fast: but explainable as the relative speed of cars 
    % in the opposite lane on a highway would be ~2x100 kmph = 55 m/s
    % for cars in the same lane, this would cause extreme blur 
    LPD_EXP_MIN = 0.003; % sec
    LPD_EXP_MAX = 0.005; % sec
    rng('shuffle');  % for randomness across runs, otherwise -batch defaults to a seed
    
    % Camera Params
    cam_speed = CAM_SPEED_MIN + (CAM_SPEED_MAX - CAM_SPEED_MIN) * rand; % m/s
    te_lpd = LPD_EXP_MIN + (LPD_EXP_MAX - LPD_EXP_MIN) * rand; % sec
    te_spd = 0.0111; % SPD; 11.11 ms = 1/90 sec
    fps = 60; % fps
    sim_time = Nframes / fps; % seconds
    resolution = [1920 1080];
    
    %% Load Scene
    % Load metadata if it exists
    meta_file = fullfile(piRootPath, 'data', 'scenes', sceneID, ...
        sprintf('%s.mat', sceneID));
    if isfile(meta_file)
        sceneMeta = load(meta_file);
    else
        error('Metadata file not found!');
    end

    % Save camera speed and exposure to metadata
    sceneMeta.sceneMeta.cameraSpeed = cam_speed;
    sceneMeta.sceneMeta.lpd_exposure = te_lpd;
    sceneMeta.sceneMeta.spd_exposure = te_spd;
    sceneMeta.sceneMeta.fps = fps;

    % save new metadata
    parentDir = fileparts(meta_file);
    [~,base,ext] = fileparts(meta_file);
    alt_file = fullfile(parentDir, [base '_lf' ext]);
    save(alt_file, '-struct', 'sceneMeta');
    
    % Load scene and light groups
    thisR_skymap = piRead(fullfile(piRootPath, 'data', 'scenes', sceneID, ...
    sprintf('%s_skymap', sceneID), sprintf('%s_skymap.pbrt', sceneID)));

    thisR_otherlights = piRead(fullfile(piRootPath, 'data', 'scenes', sceneID, ...
        sprintf('%s_otherlights', sceneID), sprintf('%s_otherlights.pbrt', sceneID)));

    thisR_headlights = piRead(fullfile(piRootPath, 'data', 'scenes', sceneID, ...
        sprintf('%s_headlights', sceneID), sprintf('%s_headlights.pbrt', sceneID)));

    thisR_streetlights = piRead(fullfile(piRootPath, 'data', 'scenes', sceneID, ...
        sprintf('%s_streetlights', sceneID), sprintf('%s_streetlights.pbrt', sceneID)));
    
    recipes = {thisR_otherlights, thisR_headlights, thisR_streetlights, thisR_skymap};
    
    %% Start editing the recipe
    % Motion control loop
    for ii = 1:numel(recipes)
        %% Setup
        thisR = recipes{ii};
        thisR.set('film resolution', resolution);
        thisR.set('rays per pixel', 1024);
        thisR.set('n bounces', 4);
        thisR.set('scale', [1 1 1]); % necessary for active transform directions
        thisR.useDB = 1;
    
        % Separate SPD and LPD recipes (dual exposure)
        outputDir = thisR.get('output dir');
        if ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end
        sceneFolder = thisR.get('input basename');
        [~, name, ext] = fileparts(thisR.get('output file'));
        pbrtFilename = [name ext];
        currName    = thisR.get('output basename');
        fprintf('Processing %s\n', currName);
    
        thisR_spd = copy(thisR);
        spd_outputFolder = fullfile(outputDir, 'spd/');
        spd_outputFile = fullfile(spd_outputFolder, pbrtFilename);
        thisR_spd.set('output file', spd_outputFile);
    
        thisR_lpd = copy(thisR);
        lpd_outputFolder = fullfile(outputDir, 'lpd/');
        lpd_outputFile = fullfile(lpd_outputFolder, pbrtFilename);
        thisR_lpd.set('output file', lpd_outputFile);
        
        %% Camera Motion
        % constant speed forward motion along -Z
        % PBRTv4 active transform; separately for SPD and LPD
        % this achieves motion blur over different exposures
        transform_time = 1 / fps; 
        
        thisR_spd.set('camera exposure', te_spd);
        thisR_spd.set('transform times start', 0.0);
        thisR_spd.set('transform times end', transform_time);
    
        thisR_lpd.set('camera exposure', te_lpd);
        thisR_lpd.set('transform times start', 0.0);
        thisR_lpd.set('transform times end', transform_time);
         
        cam_dist_total = cam_speed * sim_time;
        cam_dist_pframe = cam_dist_total / Nframes;
        
        % Important: In PBRTv4, we start from the origin, not thisR.get('from')
        % Set start and end positions for the camera
        % this motion is performed during the frame exposure time
        start_cam_pos = [0 0 0];
        end_cam_pos = start_cam_pos;
        end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
        
        for kk = 1:Nframes
            fprintf('Writing Frame: %02d\n', kk);
            idxStr = sprintf('%02d', kk);
    
            spd_outFile = sprintf('%s/%s_%s.pbrt', spd_outputFolder, currName, idxStr);
            thisR_spd.set('outputFile', spd_outFile);
    
            lpd_outFile = sprintf('%s/%s_%s.pbrt', lpd_outputFolder, currName, idxStr);
            thisR_lpd.set('outputFile', lpd_outFile);
        
            thisR_spd.set('camera motion translate start', start_cam_pos);
            thisR_spd.set('camera motion translate end', end_cam_pos);
    
            thisR_lpd.set('camera motion translate start', start_cam_pos);
            thisR_lpd.set('camera motion translate end', end_cam_pos);
    
            % Write PBRT files
            piWrite(thisR_spd, 'remoterender', false);
            piWrite(thisR_lpd, 'remoterender', false);
            
            % update camera position for next frame
            start_cam_pos = end_cam_pos;
            end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
        end
    end
end