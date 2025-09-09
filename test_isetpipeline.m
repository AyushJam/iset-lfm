%% Test ISETAuto Rendering

%%
ieInit;
if ~piDockerExists, piDockerConfig; end

%%
thisR = piRead(['./iset3d-tiny/data/scenes/web/1112153442_skymap' ...
    '/1112153442_skymap.pbrt']);
% thisR = piRecipeDefault('scene name','simplescene');

%%
thisR.set('film resolution', [960 540]);
thisR.set('rays per pixel', 256);
thisR.set('n bounces', 4); % Number of bounces

%%
thisR.useDB = 1;
piWrite(thisR, 'remoterender', true);

%%
thisD = isetdocker;
scene = piRender(thisR, 'docker', thisD);

%%
% sceneWindow(scene);
