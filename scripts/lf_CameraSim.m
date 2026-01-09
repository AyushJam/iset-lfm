% lf_CameraSim.m: Pre-render light control version
% 
% Takes four inputs: 
% imageID (string), frameId (string), weights for spd and lpd, 
% combines four light groups to create the scene and
% runs ISETCam simulator to generate captured images.
% 
% Flicker simulation can be pre-render or post-render,
% this script is common for both routes.
% 
% For pre-render light control, see lf_RunCamera.m
% For post-render light control, see lf_CamSim_LightCtrl.m
% 
% By changing the weights of the four light groups, 
% different ambient lighting conditions can be simulated (day/night).
% 
% Input: 
% - ImageID: '1112160403' etc.
% - frameId: '01', '02', ..., '10'
% 
% Authored by Ayush Jamdar (August, 2025)
% Based on ISETHDR examples by Zhenyi Liu

function lf_CameraSim(imageID, frameId, wgts_spd, wgts_lpd)
% where frameId is a string like '01', '02', ..., '10'
    %% Stage 0
    % ieInit; % Run IeInit from cmdline first. 
    % Can't place it here as it clears frameId

    % Weight ordering:
    % headlight, street light, other, sky light
    
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
    pixelSize = 2.8e-6; % LPD/SPD difference is accounted in sensor fill factor
    scene_spd = lf_SceneCreate(imageID,'weights',wgts_spd,'denoise',true, ...
        'frameId', frameId, 'sensorType', 'spd');
    scene_lpd = lf_SceneCreate(imageID,'weights',wgts_lpd,'denoise',true, ...
        'frameId', frameId, 'sensorType', 'lpd');  

    opticalImage_spd = oiCompute(oi, scene_spd,'aperture',aperture,'crop', ...
        true,'pixel size',pixelSize);
    opticalImage_lpd = oiCompute(oi, scene_lpd,'aperture',aperture,'crop', ...
        true,'pixel size',pixelSize);
    
    %% Stage 2
    expTime_spd = 20e-3; % Integration time, taken from ISETHDR
    expTime_lpd = 10e-3; 
    % we don't treat this as scene radiance exposure time
    % but a sensor gain as exposure time is already accounted in scene creation
    satLevel = 0.95;
    sensorSize = [1082 1926];
    
    arrayType = 'ovt';
    
    sensorArray = lf_sensorCreateArray('array type', arrayType,...
        'exp time spd', expTime_spd, ...
        'exp time lpd', expTime_lpd, ...
        'quantizationmethod', 'analog', ...
        'size',sensorSize);
    
    [sensorCombined, sensorArraySplit] = lf_sensorComputeArray( ...
        sensorArray, opticalImage_spd, opticalImage_lpd, ...
        'method', 'saturated', 'saturated', satLevel);
    
    %% Stage III
    % Also Stage IV: Save images
    % Moved to Stage III because
    % ISETCam uses gamma from the last ipWindow
    % This is fragile, if you change gamma in the ipWindow, 
    % it will not reflect in the already saved imags
    
    ipLPD = ipCreate;
    sensorLPDLCG = sensorArraySplit(1);
    ipLPDLCG = ipCompute(ipLPD, sensorLPDLCG, 'hdr white', true);
    ipWindow(ipLPDLCG,'render flag','rgb','gamma',0.7); % works if a GUI is available

    rgb = ipGet(ipLPDLCG,'srgb');
    fname = fullfile(isetlfmRootPath,'data', imageID, ...
        sprintf('lpd-lcg-%s.png', frameId));
    outDir = fileparts(fname);
    if ~exist(outDir,'dir')
        mkdir(outDir);
    end
    imwrite(rgb,fname);
    
    ipLPDHCG = ipCreate;
    sensorLPDHCG = sensorArraySplit(2);
    ipLPDHCG = ipCompute(ipLPDHCG,sensorLPDHCG,'hdr white',true);
    ipWindow(ipLPDHCG,'render flag','rgb','gamma',0.7);

    rgb = ipGet(ipLPDHCG,'srgb');
    fname = fullfile(isetlfmRootPath,'data', imageID, ...
        sprintf('lpd-hcg-%s.png', frameId));
    imwrite(rgb,fname);
    
    ipSPD = ipCreate;
    sensorSPD = sensorArraySplit(3);
    ipSPD = ipCompute(ipSPD,sensorSPD,'hdr white',true);
    ipWindow(ipSPD,'render flag','rgb','gamma',0.5);

    rgb = ipGet(ipSPD,'srgb');
    fname = fullfile(isetlfmRootPath,'data', imageID, ...
        sprintf('spd-%s.png', frameId));
    imwrite(rgb,fname);
    
    ipSplit = ipCreate;
    ipSplit = ipCompute(ipSplit,sensorCombined,'hdr white',true);
    ipWindow(ipSplit,'render flag','rgb','gamma',0.3);
    
    rgb = ipGet(ipSplit,'srgb');
    fname = fullfile(isetlfmRootPath,'data', imageID, ...
        sprintf('combined-%s.png', frameId));
    imwrite(rgb,fname);
    
end