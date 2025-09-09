function test_camera(frameId)
% TEST_CAMERA(i) where i is a string like '01', '02', ..., '10'
    %% Stage 0
    % ieInit; % Run IeInit from cmdline first. 
    % Can't place it here as it clears frameId
    imageID = '1112153442';
    wgts = [0.3 0.01 0.01 0.1];
    % headlight, street light, other, sky light
    
    [oi,wvf] = oiCreate('wvf');
    params = wvfApertureP;
    params.nsides = 0;
    params.dotmean = 0;
    params.dotsd = 0;
    params.dotopacity = 0.5;
    params.dotradius = 50;
    params.linemean = 0;
    params.linesd = 0;
    params.lineopacity = 0.5;
    params.linewidth = 2;
    
    aperture = wvfAperture(wvf,params);
    oi = oiSet(oi,'wvf zcoeffs',0,'defocus');
    
    %% Stage 1
    pixelSize = 3e-6;
    scene = lf_SceneCreate(imageID,'weights',wgts,'denoise',false, ...
        'frameId', frameId);
    opticalImage = oiCompute(oi, scene,'aperture',aperture,'crop', ...
        true,'pixel size',pixelSize);
    
    %% Stage 2
    expTime = 16e-3 * 10; % CHECK
    satLevel = 0.95;
    sensorSize = [1082 1926];
    
    arrayType = 'ovt';
    
    sensorArray = sensorCreateArray('array type', arrayType,...
        'pixel size same fill factor',pixelSize, ...
        'exp time', expTime, ...
        'quantizationmethod', 'analog', ...
        'size',sensorSize);
    
    [sensorCombined, sensorArraySplit] = sensorComputeArray(sensorArray, ...
        opticalImage, 'method', 'saturated', ...
        'saturated', satLevel);
    
    %% Stage III
    ipLPD = ipCreate;
    sensorLPDLCG = sensorArraySplit(1);
    ipLPDLCG = ipCompute(ipLPD, sensorLPDLCG, 'hdr white', true);
    % ipWindow(ipLPDLCG,'render flag','rgb','gamma',0.5);
    
    ipLPDHCG = ipCreate;
    sensorLPDHCG = sensorArraySplit(2);
    ipLPDHCG = ipCompute(ipLPDHCG,sensorLPDHCG,'hdr white',true);
    % ipWindow(ipLPDHCG,'render flag','rgb','gamma',0.5);
    
    ipSPD = ipCreate;
    sensorSPD = sensorArraySplit(3);
    ipSPD = ipCompute(ipSPD,sensorSPD,'hdr white',true);
    % ipWindow(ipSPD,'render flag','rgb','gamma',0.5);
    
    ipSplit = ipCreate;
    ipSplit = ipCompute(ipSplit,sensorCombined,'hdr white',true);
    % ipWindow(ipSplit,'render flag','rgb','gamma',0.5);
    
    
    %% Stage IV
    rgb = ipGet(ipSplit,'srgb');
    fname = fullfile(isethdrsensorRootPath,'data', imageID,'combined.png');
    imwrite(rgb,fname);
    
    rgb = ipGet(ipLPDLCG,'srgb');
    fname = fullfile(isethdrsensorRootPath,'data', imageID, ...
        sprintf('lpd-lcg-%s.png', frameId));
    imwrite(rgb,fname);
    
    rgb = ipGet(ipLPDHCG,'srgb');
    fname = fullfile(isethdrsensorRootPath,'data', imageID,'lpd-hcg.png');
    imwrite(rgb,fname);
    
    rgb = ipGet(ipSPD,'srgb');
    fname = fullfile(isethdrsensorRootPath,'data', imageID,'spd.png');
    imwrite(rgb,fname);
    
end