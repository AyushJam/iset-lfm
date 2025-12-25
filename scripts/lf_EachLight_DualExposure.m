% lf_EachLight_DualExposure
% 
% Script to create dual-exposure (LPD and SPD) PBRT files
% N frames per light group per scene for a moving camera
% 
% Light Control: 
% - [Key Idea] LEDs: each light in the light groups of headlights and 
%   otherlights is assigned a random PWM frequency and duty cycle. 
% - The light intensity is modulated frame-by-frame according to an LED flicker model.
% - Non-LED lights (streetlights, skymap) are kept constant.
% - This is "pre-render light control". It is slower but controls each individual light. 
% - For post-render light control, see lf_DualExposure.m
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
% Camera Simulation: TODO: Update filenames
% - See lf_RunCameraLocal.m and lf_RunCameraRemote.m
% Authored by Ayush M. Jamdar (August 2025).
% 

function lf_EachLight_DualExposure(sceneID, Nframes)
    % DON'T run ieInit here; it will delete input args
    % ieInit; % Run it in cmd win before every session
    
    %% Hyperparams; change as needed
    DUTY_MIN = 0.1; % minimum duty cycle
    DUTY_MAX = 0.4; % reduced to get noticable light flicker
    FPWM_MIN = 90; % minimum PWM frequency in Hz
    FPWM_MAX = 110;
    gain = 1; % intensity multiplier
    rng(12); % seed for rand
    
    % Camera Params
    cam_speed = 60; % meters per second;
    te_lpd = 0.005; % exposure duration in sec; LPD; 5 ms
    te_spd = 0.0111; % SPD; 11.11 ms = 1/90 sec
    fps = 60; % fps
    sim_time = Nframes / fps; % seconds
    resolution = [1920 1080];
    
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
    
    %% Load recipes
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
    % light and motion control loop
    
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
    
        %% LED Flicker
        % Control each light individually if LED
        lights = thisR.get('lights');
        
        % % if otherlights and headlights are LEDs
        % if (thisR == thisR_otherlights) || (thisR == thisR_headlights) 
        % if only otherlights are LEDs
        if (thisR == thisR_otherlights)

            % to save the LED data
            nL = numel(lights);
            led_node_index  = zeros(nL,1);
            led_name        = strings(nL,1);
            duty_cycle      = zeros(nL,1);
            f_pwm_hz        = zeros(nL,1);
            t_start_ms      = zeros(nL,1);
    
            phi_by_light_spd = containers.Map('KeyType','double','ValueType','any');
            phi_by_light_lpd = containers.Map('KeyType','double','ValueType','any');
            
            % for each light
            for lidx = 1:nL
                nodeIdx = lights(lidx);
                led_node_index(lidx) = nodeIdx; 
    
                % get node name
                if isfield(thisR.assets.Node{nodeIdx}, 'name') ...
                        && ~isempty(thisR.assets.Node{nodeIdx}.name)
                    nm = thisR.assets.Node{nodeIdx}.name;
                else
                    nm = sprintf('node_%d', nodeIdx);
                end
                led_name(lidx) = string(nm);     
    
                % get random PWM parameters for this light
                duty = DUTY_MIN + (DUTY_MAX - DUTY_MIN) * rand; 
                fpwm = FPWM_MIN + (FPWM_MAX - FPWM_MIN) * rand;
                tp = 1000 / fpwm; % PWM period in ms
                ts = tp * rand; % start time / led-camera phase offset
                A = 1; % amplitude
                offset = 0; % amplitude offset
    
                % store params for CSV 
                duty_cycle(lidx) = duty;
                f_pwm_hz(lidx)   = fpwm;
                t_start_ms(lidx) = ts;
    
                % get change in radiant exposure over frames
                % returned phi starts at time=0, phi=0
                % time inputs in ms
                % 1/2: SPD
                py_out_spd = m.phi_over_frames(duty, fpwm, te_spd*1000, ts, fps, 1, ...
                    A, offset); % run for 1 sec (get more than needed)
                time_np_spd = py_out_spd{1};
                phi_np_spd = py_out_spd{2};
                time_spd = np2mat(time_np_spd); % convert to matlab double
                phi_t_spd = np2mat(phi_np_spd);
                phi_by_light_spd(lidx) = phi_t_spd;
    
                % 2/2: LPD
                py_out_lpd = m.phi_over_frames(duty, fpwm, te_lpd*1000, ts, fps, 1, ...
                    A, offset); % run for 1 sec (get more than needed)
                time_np_lpd = py_out_lpd{1};
                phi_np_lpd = py_out_lpd{2};
                time_lpd = np2mat(time_np_lpd); % convert to matlab double
                phi_t_lpd = np2mat(phi_np_lpd);
                phi_by_light_lpd(lidx) = phi_t_lpd;
            end
    
            % Build table and write CSV
            T = table(led_node_index, led_name, duty_cycle, f_pwm_hz, t_start_ms, ...
                'VariableNames', {'light_node_index','name','duty_cycle','f_pwm_hz','ts_ms'});
            
            out_csv = fullfile(thisR.get('output dir'), 'led_params.csv');   
            writetable(T, out_csv);
            
            fprintf('Wrote LED parameters to: %s\n', out_csv);
        end
    
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
    
            % Flicker effect
            % set light intensities according to LED flicker model
            tic;
            if (thisR == thisR_otherlights) || (thisR == thisR_headlights) 
            lights = thisR.get('lights');
                % for each LED light
                for lidx = 1:numel(lights)
                    % SPD
                    phi_thisLight = phi_by_light_spd(lidx); % get that intensity array
                    brightness = gain * phi_thisLight(kk+1); % skip first 0
                    thisR_spd.set('light', lights(lidx), 'specscale', brightness);
                    % this specscale line is the bottleneck (takes a second for
                    % each light)
                    
                    % LPD
                    phi_thisLight = phi_by_light_lpd(lidx);
                    brightness = gain * phi_thisLight(kk+1); % skip first 0
                    thisR_lpd.set('light', lights(lidx), 'specscale', brightness);
                    
                end
            else
                % non-LED lights
                for lidx = 1:numel(lights)
                    thisR_spd.set('light', lights(lidx), 'specscale', gain);
                    thisR_lpd.set('light', lights(lidx), 'specscale', gain);
                end
            end
            % this step usually takes the longest time
            disp(['Time to set lights: ', num2str(toc), ' seconds']);
        
            % Write PBRT files
            piWrite(thisR_spd, 'remoterender', false);
            piWrite(thisR_lpd, 'remoterender', false);
            
            % update camera position for next frame
            start_cam_pos = end_cam_pos;
            end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
        end
    end
end