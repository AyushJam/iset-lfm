function make_video_lpd_lcg(imageID)
% Build a 10-fps video from lpd-lcg-01..10.png in the given directory.

  % baseDir = '/Users/ayushjam/Desktop/iset/isethdrsensor/data/1112153442';
  baseDir = fullfile(isethdrsensorRootPath, 'data', imageID);
  fps     = 2;
  outFile = fullfile(baseDir, 'lpd-lcg.mp4');  % MPEG-4 (H.264) container

  % Create writer
  vw = VideoWriter(outFile, 'MPEG-4');  % requires R2016a+ and OS codec support
  vw.FrameRate = fps;
  vw.Quality   = 95;                    % 0–100 (higher = better, larger file)
  open(vw);

  % Write frames lpd-lcg-01.png ... lpd-lcg-10.png
  firstWH = [];
  nFrames = 10;

  for k = 1:nFrames
    idx = sprintf('%02d', k);
    imgPath = fullfile(baseDir, sprintf('lpd-lcg-%s.png', idx));

    if ~isfile(imgPath)
      close(vw);
      error('Missing frame: %s', imgPath);
    end

    I = imread(imgPath);

    % Ensure RGB
    if size(I,3) == 1
      I = repmat(I, [1 1 3]);
    end

    % Enforce consistent size (resize others to match the first)
    if isempty(firstWH)
      firstWH = [size(I,1) size(I,2)];
    else
      if any([size(I,1) size(I,2)] ~= firstWH)
        I = imresize(I, firstWH);
      end
    end

    writeVideo(vw, I);
  end

  close(vw);
  fprintf('Wrote video: %s (%d frames @ %d fps)\n', outFile, nFrames, fps);
end
