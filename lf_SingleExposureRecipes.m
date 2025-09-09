%% Test ISETAuto Rendering

%%
ieInit;
if ~piDockerExists, piDockerConfig; end

%% Hyperparams
DUTY_MIN = 0.1;
DUTY_MAX = 0.8;
FPWM_MIN = 90;
FPWM_MAX = 110;
rng(42); % seed for rand

%% Flicker Model Init

flickerModulePath = './model.py';

if count(py.sys.path, flickerModulePath) == 0
    insert(py.sys.path, int32(0), flickerModulePath);
end

m = py.importlib.import_module('model'); 
py.importlib.reload(m); 

np2mat = @(np) cell2mat(cell(py.numpy.as ...
array(np).tolist()));

%% Camera Params
te = 0.005; % sec
fps = 60; % fps
Nframes = 10;
sim_time = Nframes / fps; % seconds
% Nframes = sim_time * fps; 

%% Load recipes
thisR_skymap = piRead(['./iset3d-tiny/data/scenes/web/1112153442_skymap' ...
    '/1112153442_skymap.pbrt']);
thisR_otherlights = piRead(['./iset3d-tiny/data/scenes/web/1112153442_otherlights' ...
    '/1112153442_otherlights.pbrt']);
thisR_headlights = piRead(['./iset3d-tiny/data/scenes/web/1112153442_headlights' ...
    '/1112153442_headlights.pbrt']);
thisR_streetlights = piRead(['./iset3d-tiny/data/scenes/web/1112153442_streetlights' ...
    '/1112153442_streetlights.pbrt']);

recipes = {thisR_streetlights, thisR_skymap, thisR_otherlights, thisR_headlights};

%% Start editing the recipe

for ii = 1:numel(recipes)

    %% Setup
    thisR = recipes{ii};
    thisR.set('film resolution', [960 540]);
    thisR.set('rays per pixel', 1024);
    thisR.set('n bounces', 4);
    thisR.set('scale', [1 1 1]);
    thisR.useDB = 1;

    pbrtOutputFile = thisR.get('output file'); 
    outputFolder   = thisR.get('output folder'); 
    sceneFolder    = thisR.get('input basename');
    currName       = thisR.get('output basename');

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

        phi_by_light = containers.Map('KeyType','double','ValueType','any');
        
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
            py_out = m.phi_over_frames(duty, fpwm, te*1000, ts, fps, 1, ...
                A, offset); % run for 1 sec (get more than needed)
            time_np = py_out{1};
            phi_np = py_out{2};
            time = np2mat(time_np); % convert to matlab double
            phi_t = np2mat(phi_np);

            phi_by_light(lidx) = phi_t;
        end
    end

    % Build table and write CSV
    T = table(led_node_index, led_name, duty_cycle, f_pwm_hz, t_start_ms, ...
        'VariableNames', {'light_node_index','name','duty_cycle','f_pwm_hz','ts_ms'});
    
    out_csv = fullfile(thisR.get('output dir'), 'led_params.csv');   
    writetable(T, out_csv);
    
    fprintf('Wrote LED parameters to: %s\n', out_csv);

    %% Camera Motion
    transform_time = 1 / fps; 
    
    thisR.set('camera exposure', te);
    thisR.set('transform times start', 0.0);
    thisR.set('transform times end', transform_time);
    
    cam_speed = 15; % meters per second; 
    cam_dist_total = cam_speed * sim_time;
    cam_dist_pframe = cam_dist_total / Nframes;
    
    % Important: In PBRTv4, we start from the origin, not thisR.get('from')
    start_cam_pos = [0 0 0];
    end_cam_pos = start_cam_pos;
    end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
    
    for kk = 1:Nframes
        fprintf('Writing Frame: %02d\n', kk);
        idxStr = sprintf('%02d', kk);
        outFile = sprintf('%s/%s_%s.pbrt', outputFolder, currName, idxStr);
        thisR.set('outputFile', outFile);
    
        thisR.set('camera motion translate start', start_cam_pos);
        thisR.set('camera motion translate end', end_cam_pos);

        % Flicker effect
        gain = 10;
        if (thisR == thisR_otherlights) || (thisR == thisR_headlights) 
        lights = thisR.get('lights');
            % for each LED light
            for lidx = 1:numel(lights)
                phi_thisLight = phi_by_light(lidx);
                brightness = gain * phi_thisLight(kk+1); % skip first 0
                thisR.set('light', lights(lidx), 'specscale', brightness);
            end
        else
            % non-LED lights
            for lidx = 1:numel(lights)
                thisR.set('light', lights(lidx), 'specscale', gain);
            end
        end
    
        piWrite(thisR, 'remoterender', true);
    
        start_cam_pos = end_cam_pos;
        end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
    end

    %% Upload to Orange
    thisD = isetdocker; 
    iDockerPrefs   = getpref('ISETDocker');
    
    % if isfield(iDockerPrefs,'PBRTContainer')
    %     % Test that the container is running remotely
    %     result = obj.dockercmd('psfind','string',iDockerPrefs.PBRTContainer);
    % 
    %     % Couldn't find it.  Restart.
    %     if isempty(result), obj.startPBRT; end
    % else
    %     % No PBRTContainer specified, so restart.
    %     obj.startPBRT();
    % end
    % 
    % ourContainer = getpref('ISETDocker','PBRTContainer');
    
    if ispc,     flags = '-i ';
    else,        flags = '-it ';
    end
    
    [~, sceneDir, ~] = fileparts(outputFolder);
    
    if ~isempty(getpref('ISETDocker','remoteHost'))
        if ispc
            remoteSceneDir = [getpref('ISETDocker','workDir') '/' sceneFolder];
        else
            remoteSceneDir = fullfile(getpref('ISETDocker','workDir'),sceneFolder);
        end
        % sync files from local folder to remote
        thisD.upload(outputFolder, remoteSceneDir,{'renderings',[currName,'.mat']});
    
        outF = fullfile(remoteSceneDir,'renderings',[currName,'.exr']);
        
        % check if there is renderings folder
        sceneFolder = dir(thisD.sftpSession,fullfile(remoteSceneDir));
        renderingsDir = true;
        for n = 1:numel(sceneFolder)
            if sceneFolder(n).isdir && strcmp(sceneFolder(n).name,'renderings')
                renderingsDir = false;
            end
        end
        if renderingsDir
            mkdir(thisD.sftpSession,fullfile(remoteSceneDir,'renderings'));
        end
    else
        disp('Cannot render locally');
    end
end




