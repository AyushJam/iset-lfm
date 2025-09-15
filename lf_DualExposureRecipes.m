%% ISETAuto Scene Recipe Editing
function lf_DualExposureRecipes(sceneID, Nframes)

    % %%
    % ieInit;
    % if ~piDockerExists, piDockerConfig; end
    
    %% Hyperparams
    DUTY_MIN = 0.1;
    DUTY_MAX = 0.4; % reduced to force light flicker
    FPWM_MIN = 90;
    FPWM_MAX = 110;
    gain = 1; % intensity multiplier
    rng(18); % seed for rand
    
    % Camera Params
    cam_speed = 0; % meters per second;
    te_lpd = 0.005; % exposure duration in sec; LPD
    te_spd = 0.0111; % SPD
    fps = 60; % fps
    sim_time = Nframes / fps; % seconds
    
    %% Flicker Model Init
    
    flickerModulePath = fullfile(getenv('HOME'), 'iset', 'iset-lfm');
    
    if count(py.sys.path, flickerModulePath) == 0
        insert(py.sys.path, int32(0), flickerModulePath);
    end
    
    m = py.importlib.import_module('model'); 
    py.importlib.reload(m); 
    
    np2mat = @(np) cell2mat(cell(py.numpy.asarray(np).tolist()));
    
    %% Load recipes
    thisR_skymap = piRead(sprintf(['./iset3d-tiny/data/scenes/%s/%s_skymap' ...
        '/%s_skymap.pbrt'], sceneID, sceneID, sceneID));
    thisR_otherlights = piRead(sprintf(['./iset3d-tiny/data/scenes/%s/%s_otherlights' ...
        '/%s_otherlights.pbrt'], sceneID, sceneID, sceneID));
    thisR_headlights = piRead(sprintf(['./iset3d-tiny/data/scenes/%s/%s_headlights' ...
        '/%s_headlights.pbrt'], sceneID, sceneID, sceneID));
    thisR_streetlights = piRead(sprintf(['./iset3d-tiny/data/scenes/%s/%s_streetlights' ...
        '/%s_streetlights.pbrt'], sceneID, sceneID, sceneID));
    
    recipes = {thisR_otherlights, thisR_headlights, thisR_streetlights, thisR_skymap};
    % recipes = {thisR_otherlights};
    
    %% Start editing the recipe
    
    for ii = 1:numel(recipes)
    
        %% Setup
        thisR = recipes{ii};
        thisR.set('film resolution', [960 540]);
        thisR.set('rays per pixel', 1024);
        thisR.set('n bounces', 4);
        thisR.set('scale', [1 1 1]);
        thisR.useDB = 1;
    
        % Separate SPD and LPD recipes
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
        lights = thisR.get('lights');
    
        if (thisR == thisR_otherlights) || (thisR == thisR_headlights) 
            % to save the LED data
            nL = numel(lights);
            led_node_index = zeros(nL,1);
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
    
                % get random PWM parameters
                duty = DUTY_MIN + (DUTY_MAX - DUTY_MIN) * rand; 
                fpwm = FPWM_MIN + (FPWM_MAX - FPWM_MIN) * rand;
                tp = 1000 / fpwm; % PWM period in ms
                ts = tp * rand; % start time / led-camera phase offset
                A = 1;
                offset = 0;
    
                % store params for CSV
                duty_cycle(lidx) = duty;
                f_pwm_hz(lidx)   = fpwm;
                t_start_ms(lidx) = ts;
    
                % get change in radiant exposure over frames
                % returned phi starts at time=0, phi=0
                % time inputs in ms
                % SPD
                py_out_spd = m.phi_over_frames(duty, fpwm, te_spd*1000, ts, fps, 1, ...
                    A, offset); % run for 1 sec (get more than needed)
                time_np_spd = py_out_spd{1};
                phi_np_spd = py_out_spd{2};
                time_spd = np2mat(time_np_spd); % convert to matlab double
                phi_t_spd = np2mat(phi_np_spd);
                phi_by_light_spd(lidx) = phi_t_spd;
    
                % LPD
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
            disp(['Time to set lights: ', num2str(toc), ' seconds']);
        
            piWrite(thisR_spd, 'remoterender', false);
            piWrite(thisR_lpd, 'remoterender', false);
        
            start_cam_pos = end_cam_pos;
            end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
        end
    end
end