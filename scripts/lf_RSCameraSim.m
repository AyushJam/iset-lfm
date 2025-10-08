% lf_RSCameraSim.m
% 
% Simulates a rolling shutter camera capturing a night 
% driving scene with flickering lights.
% 
% Procedure: 
% - We follow the post-render light control method to control 
%   the brightness of LED light groups. 
% - We combine the light groups with different weights 
%   to create a new scene for EACH ROW capture.
% - The flicker model generates the weights for each row capture.
% - We then combine the diagonal rows from a frame cuboid hence obtained
%   to create the final rolling shutter image.
% 
% Notes: 
% - While we used a static scene to demonstrate the method, 
%   the method can be extended to dynamic scenes but turning this 
%   script into a function like lf_RunCamera/lf_CameraSim.
% 
% Authored by Ayush Jamdar (Sept, 2025)
% with inputs from Brian Wandell.
 

% function lf_RSCameraSim(imageID, frameId)
% where i is a string like '01', '02', ..., '10'

    %% Flicker Model Init
    flickerModulePath = fullfile(getenv('HOME'), 'iset', 'iset-lfm');
    
    if count(py.sys.path, flickerModulePath) == 0
        insert(py.sys.path, int32(0), flickerModulePath);
    end
    
    m = py.importlib.import_module('model'); 
    py.importlib.reload(m); 
    
    np2mat = @(np) cell2mat(cell(py.numpy.asarray(np).tolist()));
    

    %% Stage 0
    % ieInit; % Run IeInit from cmdline first. 
    % Don't place it here as it clears frameId

    % camera params init
    sensor = sensorCreate; 
    pixelSize = 2.8e-6;
    expTime = 10e-3; % this is the sensor integtration time, not the RS exp
    sensor = sensorSet(sensor, 'pixel size constant fill factor', pixelSize);
    sensorSize = [540, 960];
    sensor = sensorSet(sensor, 'size', sensorSize);
    sensor = sensorSet(sensor, 'exp time', expTime);

    perRow = 10e-6; % read out time per row / line time
     
    % total number of captures to simulate
    % nFrames = sensorSize(1) + round(expTime/perRow);
    nFrames = sensorSize(1); % simplified

    % Initial weights
    imageID = '1112184733';
    wgts = [1.0    0.5    1   0.01]; % night scene
    % headlight, street light, other, sky light

    % Light group characteristics
    D_headlgts = 0.3; % duty cycle
    fp_headlgts = 95; % flicker frequency in Hz
    ts_headlgts = 0.15 * (1000 / fp_headlgts); % cycle time in ms

    D_otherlgts = 0.2;
    fp_otherlgts = 105;
    ts_otherlgts = 0.2 * (1000 / fp_otherlgts);
    te = 5; % ms; exp time, different from above exp time
    
    % func takes time input in ms
    phi_headlgts = np2mat(m.phi_over_rows(D_headlgts, fp_headlgts, te, ...
        ts_headlgts, perRow*1000, nFrames, 1, 0));

    phi_otherlgts = np2mat(m.phi_over_rows(D_otherlgts, fp_otherlgts, te, ...
        ts_otherlgts, perRow*1000, nFrames, 1, 0));

    % store the sensor volts from each sensor separately
    v = zeros(sensorSize(1), sensorSize(2), nFrames);
    
    %% Load scene exr
    lgt = {'headlights','streetlights','otherlights','skymap'};
    destPath = fullfile(isetlfmRootPath,'local',sprintf('%s_lowres', imageID));

    scenes = cell(numel(lgt,1));
    for ll = 1:numel(lgt)
        thisFile = sprintf('%s_%s.exr',imageID,lgt{ll});
        destFile = fullfile(destPath,thisFile);

        if exist(destFile, 'file')
            sprintf('%s: File exists.', destFile);
        else
            sprintf('%s: File does not exist.', destFile);
        end

        scenes{ll} = piEXR2ISET(destFile);
    end

    %%
    [oi,wvf] = oiCreate('wvf');
    params = wvfApertureP;
    params.nsides = 0;
    params.dotmean = 0;
    params.dotsd = 0;
    params.dotopacity = 0;
    params.dotradius = 0;
    params.linemean = 0;
    params.linesd = 0;
    params.lineopacity = 0;
    params.linewidth = 0;
    
    aperture = wvfAperture(wvf,params);
    oi = oiSet(oi,'wvf zcoeffs',0,'defocus');
    
    %% Stage 1
    fprintf('Processing...\n');
    for ii=1:nFrames
        fprintf('Row %03d\n', ii);

        % Update light weights for this frame/row
        wgtsThisRow = wgts;
        wgtsThisRow(1) = wgts(1) * phi_headlgts(ii); % headlight
        wgtsThisRow(3) = wgts(3) * phi_otherlgts(ii); % otherlight

        % use simulated RS weights in LPD only: testing phase
        scene = sceneAdd(scenes, wgtsThisRow);
        scene = piAIdenoise(scene);
        scene.metadata.wgts = wgtsThisRow; 
        % ieAddObject(scene); sceneWindow;

        oi = oiCompute(oi, scene,'aperture',aperture,'crop', ...
        true,'pixel size',pixelSize);

        sensor = sensorCompute(sensor, oi);

        if ii == 1
            % after the first capture, set noise to photon only
            sensor = sensorSet(sensor, 'noise flag', 1);
        end

        v(:, :, ii) = sensorGet(sensor, 'volts');
 
    end
    %%
    % % display the frames
    % colormap(gray(64));
    % fps = 7;
    % for ii = 1: nFrames
    %     imagesc(v(:, :, ii)); pause(1/fps);
    % end
    
    % final summed voltages for each row
    final = zeros(sensorSize);

    % Don't use ISET code; use RS flicker model 
    % slist = 1:round(expTime/perRow);
    % z = zeros(nFrames, 1);
    % z(slist) = 1;

    for rr = 1:sensorSize(1)
        % slightly simplified
        % slist = slist + 1;
        % z = zeros(nFrames, 1);
        % z(slist) = 1;
        % tmp = squeeze(v(rr, :, :));
        % final(rr, :) = tmp * z;
        final(rr, :) = v(rr, :, rr);
    end
    
    % image processing
    srs = sensorSet(sensor, 'volts', final);

    ip = ipCreate; 
    ip = ipCompute(ip, srs);
    
    ieAddObject(ip);
    ipWindow;
    
% end