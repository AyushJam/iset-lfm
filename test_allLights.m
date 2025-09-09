%% Test ISETAuto Rendering

%%
ieInit;
if ~piDockerExists, piDockerConfig; end

%%
% thisR = piRead(['./iset3d-tiny/data/scenes/web/1112153442_skymap' ...
%     '/1112153442_skymap.pbrt']);
% thisR = piRead(['./iset3d-tiny/data/scenes/web/1112153442_otherlights' ...
%     '/1112153442_otherlights.pbrt']);
% thisR = piRead(['./iset3d-tiny/data/scenes/web/1112153442_instanceID' ...
%     '/1112153442_instanceID.pbrt']);

%%
thisR = load('./iset3d-tiny/data/scenes/web/1112153442/1112153442.mat').thisR;
thisR.set('input file', ['./iset3d-tiny/data/' ...
    'scenes/web/1112153442/1112153442.pbrt']);
thisR.set('output file', ['./iset3d-tiny/' ...
    'local/1112153442/1112153442.pbrt']);

% The mat file does not use this field like the exported lightgroups do
% This throws an indexing error, so use an empty struct
thisR.media = struct( ...
    'list', containers.Map(), ...
    'order', {{}}, ...
    'lib', [] ...
);

NodeList = thisR.assets.Node; 
for nn = 1:numel(NodeList)
    thisNode = NodeList{nn};
    if contains(thisNode.name, {'skymap'})
        thisR.assets = thisR.assets.chop(nn);
    end
end

thisR.set('skymap', './iset3d-tiny/local/1112153442/skymaps/skymap_004.exr');

%%
thisR.set('film resolution', [960 540]);
thisR.set('rays per pixel', 1024);
thisR.set('n bounces', 4); % Number of bounces
thisR.set('scale', [1 1 1]); % [-1 1 1] is inverted: transforms fail!
thisR.useDB = 1;
thisD = isetdocker; 

pbrtOutputFile = thisR.get('output file'); 
outputFolder   = thisR.get('output folder'); 
sceneFolder    = thisR.get('input basename');
currName       = thisR.get('output basename');

%% Brighten Lights
% CHECK: should not have to do this? 
gain = 100;
lgts = thisR.get('lights');

for ii = 1:numel(lgts)
    thisR.set('light', lgts(ii), 'specscale', gain);
end

%% Camera Motion
te = 0.011; % ms
fps = 60; % fps
sim_time = 1; % seconds
Nframes = sim_time * fps; 
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

for ii = 1:1
    fprintf('Writing Frame: %02d\n', ii);
    idxStr = sprintf('%02d', ii);
    outFile = sprintf('%s/%s_%s.pbrt', outputFolder, currName, idxStr);
    thisR.set('outputFile', outFile);

    thisR.set('camera motion translate start', start_cam_pos);
    thisR.set('camera motion translate end', end_cam_pos);

    piWrite(thisR, 'remoterender', true);

    start_cam_pos = end_cam_pos;
    % end_cam_pos = end_cam_pos + 0.2 * thisR.get('lookat direction');
    % Don't use lookat direction: PBRT uses relative transforms 
    end_cam_pos(3) = end_cam_pos(3) - cam_dist_pframe;
end

%% Upload to Orange
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
    % obj.upload(localDIR, remoteDIR, {'excludes','cellarray'}})
    thisD.upload(outputFolder, remoteSceneDir,{'renderings',[currName,'.mat']});

    outF = fullfile(remoteSceneDir,'renderings',[currName,'.exr']);
    
    % check if there is renderings folder
    sceneFolder = dir(thisD.sftpSession,fullfile(remoteSceneDir));
    renderingsDir = true;
    for ii = 1:numel(sceneFolder)
        if sceneFolder(ii).isdir && strcmp(sceneFolder(ii).name,'renderings')
            renderingsDir = false;
        end
    end
    if renderingsDir
        mkdir(thisD.sftpSession,fullfile(remoteSceneDir,'renderings'));
    end
else
    disp('Cannot render locally');
end

