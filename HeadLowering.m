% =========================================================================
%  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
%  Module 2: Real-Time Head Lowering / Dropping Detection (YCbCr Skin Segmentation)
% =========================================================================
%  Accurately detects driver head lowering / nodding forward by tracking
%  facial skin area, upper-face skin density, and vertical head centroid.
%  Optimized for high sensitivity, zero-lag execution in MATLAB (60+ FPS).
%  Supports both Live Webcam and Dataset Video Sequences (dbase/head).
% =========================================================================

clear;
clc;
close all;

fprintf('\n=======================================================\n');
fprintf('  🚨 DRIVER FATIGUE MONITOR: HEAD LOWERING DETECTION   \n');
fprintf('  Multi-Metric Spatial & Color Pose Analysis (Optimized)\n');
fprintf('=======================================================\n\n');

% -------------------------------------------------------------------------
% 1. ROBUST VIDEO SOURCE ACQUISITION (Live Webcam or Dataset Video)
% -------------------------------------------------------------------------
useVideo = false;
cam = [];
vr = [];

% Clear dangling handles
try evalin('base', 'clear cam'); catch; end

fprintf('[1/4] Initializing video source...\n');
try
    cam = webcam(1);
    pause(0.5);
    sampleFrame = snapshot(cam);
    fprintf('      ✓ Connected to live webcam: %s\n', cam.Name);
catch
    useVideo = true;
    try clear cam; catch; end
    projectDir = fileparts(mfilename('fullpath'));
    if isempty(projectDir), projectDir = pwd; end
    videoPath = fullfile(projectDir, 'dbase', 'head', 'h1.mp4');
    if exist(videoPath, 'file')
        vr = VideoReader(videoPath);
        sampleFrame = readFrame(vr);
        fprintf('      ℹ️  Live webcam busy or shutter closed.\n');
        fprintf('      ✓ Loaded dataset test sequence: %s\n', videoPath);
    else
        error('Could not connect to webcam and dataset video not found.');
    end
end

% Ensure clean camera release on exit
cleanupObj = onCleanup(@() safeCleanup());

% -------------------------------------------------------------------------
% 2. MULTI-METRIC BASELINE CALIBRATION (Head upright, looking forward)
% -------------------------------------------------------------------------
fprintf('[2/4] Calibrating driver baseline posture...\n');
fprintf('      >>> PLEASE SIT UPRIGHT AND LOOK STRAIGHT AT CAMERA <<<\n');

numCalib = 5;
baseline_skin_acc = 0;
baseline_y_acc = 0;
baseline_upper_acc = 0;

for k = 1:numCalib
    if ~useVideo
        raw = snapshot(cam);
    else
        if ~hasFrame(vr), vr.CurrentTime = 0; end
        raw = readFrame(vr);
    end
    
    % Fast subsampled skin analysis (320x180)
    I_sub = single(raw(1:2:end, 1:2:end, :));
    cb = 0.148 * I_sub(:,:,1) - 0.291 * I_sub(:,:,2) + 0.439 * I_sub(:,:,3) + 128;
    cr = 0.439 * I_sub(:,:,1) - 0.368 * I_sub(:,:,2) - 0.071 * I_sub(:,:,3) + 128;
    skin_mask = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
    
    s_cnt = sum(skin_mask(:));
    [rows, ~] = find(skin_mask);
    if ~isempty(rows)
        y_cent = mean(rows);
    else
        y_cent = size(I_sub, 1) * 0.45;
    end
    
    baseline_skin_acc = baseline_skin_acc + s_cnt;
    baseline_y_acc = baseline_y_acc + y_cent;
    pause(0.06);
end

baseline_skin = max(100, baseline_skin_acc / numCalib);
baseline_y = baseline_y_acc / numCalib;

% Calibration for upper face skin (above initial centroid)
y_split = max(10, min(size(I_sub, 1) - 10, round(baseline_y)));
for k = 1:numCalib
    if ~useVideo, raw = snapshot(cam); else, raw = readFrame(vr); end
    I_sub = single(raw(1:2:end, 1:2:end, :));
    cb = 0.148 * I_sub(:,:,1) - 0.291 * I_sub(:,:,2) + 0.439 * I_sub(:,:,3) + 128;
    cr = 0.439 * I_sub(:,:,1) - 0.368 * I_sub(:,:,2) - 0.071 * I_sub(:,:,3) + 128;
    skin_mask = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
    baseline_upper_acc = baseline_upper_acc + sum(sum(skin_mask(1:y_split, :)));
end
baseline_upper = max(50, baseline_upper_acc / numCalib);

fprintf('      ✓ Baseline Skin Units:    %d\n', round(baseline_skin));
fprintf('      ✓ Baseline Vertical Pose: Y = %.1f px\n', baseline_y);
fprintf('      ✓ Baseline Upper Face:    %d units\n', round(baseline_upper));
fprintf('[3/4] Launching High-Definition HUD Display...\n');

% -------------------------------------------------------------------------
% 3. PREPARE NON-BLOCKING AUDIO ALARM
% -------------------------------------------------------------------------
fs = 8000;
t_alarm = 0:1/fs:0.35;
alarm_burst = sin(2 * pi * 880 * t_alarm);
alarm_signal = [alarm_burst, zeros(1, 400), alarm_burst, zeros(1, 400), alarm_burst];
alarmPlayer = audioplayer(alarm_signal, fs);

% -------------------------------------------------------------------------
% 4. BUILD PRESENTABLE ZERO-FLICKER HUD FIGURE
% -------------------------------------------------------------------------
[~, W, ~] = size(sampleFrame);

fig = figure('Name', 'Driver Safety Monitor - Head Lowering Detection', ...
             'NumberTitle', 'off', ...
             'Color', [0.07 0.09 0.12], ...
             'Position', [150, 100, 960, 620], ...
             'MenuBar', 'none', ...
             'ToolBar', 'none');

ax = axes('Parent', fig, 'Position', [0.02, 0.02, 0.96, 0.96]);
axis(ax, 'off');

hImg = imshow(sampleFrame, 'Parent', ax);
hold(ax, 'on');

% Pre-calculate PIP bounds
pip_h = 90;
pip_w = 120;
pip_r = 15:(14+pip_h);
pip_c = (W - pip_w - 15):(W - 16);

fprintf('[4/4] >>> SYSTEM ACTIVE & MONITORING <<<\n');
fprintf('      Lower/nod head for ~0.5s to trigger alarm.\n');
fprintf('      Close figure window or press Ctrl+C to stop.\n\n');

consec_low_frames = 0;
max_consec_threshold = 6; % ~0.5s with leaky accumulator
fps_history = zeros(1, 10);
fps_idx = 1;

% -------------------------------------------------------------------------
% 5. HIGH-SPEED REAL-TIME MONITORING LOOP
% -------------------------------------------------------------------------
while ishandle(fig)
    t_start = tic;
    
    % Capture
    if ~useVideo
        raw = snapshot(cam);
    else
        if ~hasFrame(vr), vr.CurrentTime = 0; end
        raw = readFrame(vr);
    end
    
    % Fast Vectorized Skin Segmentation
    I_sub = single(raw(1:2:end, 1:2:end, :));
    cb = 0.148 * I_sub(:,:,1) - 0.291 * I_sub(:,:,2) + 0.439 * I_sub(:,:,3) + 128;
    cr = 0.439 * I_sub(:,:,1) - 0.368 * I_sub(:,:,2) - 0.071 * I_sub(:,:,3) + 128;
    skin_mask = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
    curr_skin = sum(skin_mask(:));
    
    % Compute Vertical Head Centroid Shift
    [rows, ~] = find(skin_mask);
    if ~isempty(rows)
        curr_y = mean(rows);
    else
        curr_y = baseline_y + 30; % Head left frame
    end
    y_shift = curr_y - baseline_y; % Positive = head shifted downward
    
    % Compute Upper Face Skin Drop
    upper_skin = sum(sum(skin_mask(1:y_split, :)));
    upper_drop_pct = ((baseline_upper - upper_skin) / baseline_upper) * 100;
    
    % Multi-Metric Detection Condition:
    % 1. Y-Centroid dropped down by > 5.5 pixels OR
    % 2. Upper face skin dropped by > 12% OR
    % 3. Overall skin dropped by > 15%
    is_head_lowered = (y_shift > 5.5) || (upper_drop_pct > 12) || (curr_skin < baseline_skin * 0.85);
    
    % Leaky Accumulator (Resistant to momentary noise)
    if is_head_lowered
        consec_low_frames = min(12, consec_low_frames + 2);
    else
        consec_low_frames = max(0, consec_low_frames - 1);
    end
    
    % Alarm Trigger (Non-blocking)
    alarm_active = (consec_low_frames >= max_consec_threshold);
    if alarm_active
        if ~isplaying(alarmPlayer)
            play(alarmPlayer);
        end
        fprintf('  ⚠️  [ALARM TRIGGERED] Head lowering detected! Score: %d/%d (Shift: %+1.1f px, Upper Drop: %.0f%%)\n', ...
                consec_low_frames, max_consec_threshold, y_shift, upper_drop_pct);
    end
    
    % ---------------------------------------------------------------------
    % FAST IN-PLACE HUD COMPOSITING
    % ---------------------------------------------------------------------
    display_frame = raw;
    
    % 1. Fast PIP Skin Mask
    mask_pip = skin_mask(1:2:min(end, 2*pip_h), 1:2:min(end, 2*pip_w));
    [mh, mw] = size(mask_pip);
    pr = pip_r(1):(pip_r(1)+mh-1);
    pc = pip_c(1):(pip_c(1)+mw-1);
    
    mask_uint = uint8(mask_pip) * 220;
    display_frame(pr, pc, 1) = uint8(0);
    display_frame(pr, pc, 2) = mask_uint;
    display_frame(pr, pc, 3) = uint8(mask_uint * 0.8);
    
    display_frame(pr(1):pr(1)+1, pc, :) = 255;
    display_frame(pr(end)-1:pr(end), pc, :) = 255;
    display_frame(pr, pc(1):pc(1)+1, :) = 255;
    display_frame(pr, pc(end)-1:pc(end), :) = 255;
    
    % 2. Fast Status Banner
    banner_height = 36;
    if alarm_active
        ban_r = uint8(220); ban_g = uint8(20);  ban_b = uint8(30);
        status_text = '🚨 CRITICAL FATIGUE: HEAD LOWERED! WAKE UP!';
    elseif consec_low_frames > 2
        ban_r = uint8(220); ban_g = uint8(140); ban_b = uint8(20);
        status_text = sprintf('CAUTION: HEAD TILT / NOD DETECTED [%d/%d]', consec_low_frames, max_consec_threshold);
    else
        ban_r = uint8(20);  ban_g = uint8(160); ban_b = uint8(80);
        status_text = sprintf('HEAD: NORMAL UPRIGHT (Pose Shift: %+1.0f px)', y_shift);
    end
    
    display_frame(1:banner_height, :, 1) = ban_r;
    display_frame(1:banner_height, :, 2) = ban_g;
    display_frame(1:banner_height, :, 3) = ban_b;
    
    % Compute FPS
    loop_time = toc(t_start);
    fps = 1 / max(0.001, loop_time);
    fps_history(fps_idx) = fps;
    fps_idx = mod(fps_idx, 10) + 1;
    avg_fps = mean(fps_history(fps_history > 0));
    
    % Render Display
    try
        hImg.CData = display_frame;
        srcTag = 'Live Camera';
        if useVideo, srcTag = 'Dataset Video'; end
        title(ax, sprintf('[%s] %s  |  Upper Skin: %d / %d  |  FPS: %.1f', ...
              srcTag, status_text, round(upper_skin), round(baseline_upper), avg_fps), ...
              'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
        drawnow limitrate;
    catch
        break;
    end
    
    if useVideo
        pause(max(0.01, (1/30) - loop_time));
    end
end

fprintf('\n[STOP] Head lowering detection stopped cleanly.\n');

% -------------------------------------------------------------------------
% SAFE CLEANUP
% -------------------------------------------------------------------------
function safeCleanup()
    try
        evalin('base', 'clear cam');
        fprintf('Camera / video released successfully.\n');
    catch
    end
end
