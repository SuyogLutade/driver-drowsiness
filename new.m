% =========================================================================
%  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
%  Module 1: Real-Time Eye Drowsiness Detection (Edge-Density Method)
% =========================================================================
%  Accurately detects driver eye closure via localized edge gradient analysis.
%  Optimized with focused eye ROI, responsive thresholding, and leaky accumulator.
%  Supports both Live Webcam and Dataset Video Sequences (dbase/eyes).
% =========================================================================

clear;
clc;
close all;

fprintf('\n=======================================================\n');
fprintf('  👁️ DRIVER FATIGUE MONITOR: EYE CLOSURE DETECTION    \n');
fprintf('  High-Sensitivity Adaptive Algorithm (Optimized)      \n');
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
    videoPath = fullfile(projectDir, 'dbase', 'eyes', 'e1.mp4');
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
% 2. FOCUSED EYE ROI LOCALIZATION & BASELINE CALIBRATION
% -------------------------------------------------------------------------
fprintf('[2/4] Calibrating driver baseline (eyes open)...\n');
fprintf('      >>> LOOK STRAIGHT AT CAMERA WITH EYES OPEN <<<\n');
[H, W, ~] = size(sampleFrame);

% Focused Eye Band (Tightly centered on eye position: excludes eyebrows & mouth)
r1 = round(H * 0.32); r2 = round(H * 0.44);
c1 = round(W * 0.28); c2 = round(W * 0.72);

% Try Cascade detector once during calibration to tightly lock onto eyes
try
    faceDetector = vision.CascadeObjectDetector('FrontalFaceCART');
    bboxes = faceDetector(sampleFrame);
    if ~isempty(bboxes)
        [~, maxIdx] = max(bboxes(:, 3) .* bboxes(:, 4));
        fb = bboxes(maxIdx, :);
        ar1 = max(1, round(fb(2) + fb(4) * 0.25));
        ar2 = min(H, round(fb(2) + fb(4) * 0.48));
        ac1 = max(1, round(fb(1) + fb(3) * 0.15));
        ac2 = min(W, round(fb(1) + fb(3) * 0.85));
        if (ar2 - ar1 > 15) && (ac2 - ac1 > 25)
            r1 = ar1; r2 = ar2; c1 = ac1; c2 = ac2;
            fprintf('      ✓ Facial landmark detection locked onto eye band.\n');
        end
    end
    clear faceDetector;
catch
end

% Calibrate baseline edge density over 5 frames
numCalib = 5;
baseline_edges = 0;
for k = 1:numCalib
    if ~useVideo
        raw = snapshot(cam);
    else
        if ~hasFrame(vr), vr.CurrentTime = 0; end
        raw = readFrame(vr);
    end
    gray = single(rgb2gray(raw));
    patch = gray(r1:r2, c1:c2);
    [Gx, Gy] = gradient(patch);
    baseline_edges = baseline_edges + mean(sqrt(Gx(:).^2 + Gy(:).^2));
    pause(0.06);
end

baseline_edges = max(0.5, baseline_edges / numCalib);
% Responsive threshold: 7% drop in focused eye band triggers closure
edge_threshold = baseline_edges * 0.93;

fprintf('      ✓ Baseline Edge Density (Eyes Open): %.2f\n', baseline_edges);
fprintf('      ✓ Drowsiness Trigger Threshold:      %.2f (-7%% edge drop)\n', edge_threshold);
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
fig = figure('Name', 'Driver Safety Monitor - Eye Closure Detection', ...
             'NumberTitle', 'off', ...
             'Color', [0.07 0.09 0.12], ...
             'Position', [150, 100, 960, 620], ...
             'MenuBar', 'none', ...
             'ToolBar', 'none');

ax = axes('Parent', fig, 'Position', [0.02, 0.02, 0.96, 0.96]);
axis(ax, 'off');

hImg = imshow(sampleFrame, 'Parent', ax);
hold(ax, 'on');

corner_len = min(28, round((c2 - c1) * 0.15));
th = 3;

fprintf('[4/4] >>> SYSTEM ACTIVE & MONITORING <<<\n');
fprintf('      Close eyes for ~0.6s to trigger drowsiness alarm.\n');
fprintf('      Close figure window or press Ctrl+C to stop.\n\n');

closed_counter = 0;
consec_trigger_limit = 6; % ~0.6s with leaky accumulator
fps_history = zeros(1, 10);
fps_idx = 1;

% -------------------------------------------------------------------------
% 5. HIGH-SPEED REAL-TIME MONITORING LOOP
% -------------------------------------------------------------------------
while ishandle(fig)
    t_start = tic;
    
    % Frame Capture
    if ~useVideo
        raw = snapshot(cam);
    else
        if ~hasFrame(vr), vr.CurrentTime = 0; end
        raw = readFrame(vr);
    end
    
    % Instant ROI Gradient Magnitude
    gray = single(rgb2gray(raw));
    patch = gray(r1:r2, c1:c2);
    [Gx, Gy] = gradient(patch);
    curr_edges = mean(sqrt(Gx(:).^2 + Gy(:).^2));
    
    % Edge Delta Percentage
    edge_delta_pct = ((curr_edges - baseline_edges) / baseline_edges) * 100;
    
    % Responsive Detection: edge drops by > 14%
    is_eyes_closed = (curr_edges < edge_threshold);
    
    % Leaky Accumulator (Resistant to single-frame noise jitter)
    if is_eyes_closed
        closed_counter = min(12, closed_counter + 2);
    else
        closed_counter = max(0, closed_counter - 1);
    end
    
    % Alarm Trigger (Non-blocking)
    alarm_active = (closed_counter >= consec_trigger_limit);
    if alarm_active
        if ~isplaying(alarmPlayer)
            play(alarmPlayer);
        end
        fprintf('  ⚠️  [ALARM TRIGGERED] Prolonged eye closure! Score: %d/%d\n', ...
                closed_counter, consec_trigger_limit);
    end
    
    % ---------------------------------------------------------------------
    % FAST IN-PLACE HUD COMPOSITING
    % ---------------------------------------------------------------------
    display_frame = raw;
    
    if alarm_active
        ret_r = uint8(255); ret_g = uint8(30);  ret_b = uint8(30);
    elseif closed_counter > 2
        ret_r = uint8(240); ret_g = uint8(160); ret_b = uint8(20);
    else
        ret_r = uint8(50);  ret_g = uint8(220); ret_b = uint8(100);
    end
    
    % Corner Brackets on Eye Region
    display_frame(r1:r1+th, c1:c1+corner_len, 1) = ret_r; display_frame(r1:r1+th, c1:c1+corner_len, 2) = ret_g; display_frame(r1:r1+th, c1:c1+corner_len, 3) = ret_b;
    display_frame(r1:r1+corner_len, c1:c1+th, 1) = ret_r; display_frame(r1:r1+corner_len, c1:c1+th, 2) = ret_g; display_frame(r1:r1+corner_len, c1:c1+th, 3) = ret_b;
    display_frame(r1:r1+th, c2-corner_len:c2, 1) = ret_r; display_frame(r1:r1+th, c2-corner_len:c2, 2) = ret_g; display_frame(r1:r1+th, c2-corner_len:c2, 3) = ret_b;
    display_frame(r1:r1+corner_len, c2-th:c2, 1) = ret_r; display_frame(r1:r1+corner_len, c2-th:c2, 2) = ret_g; display_frame(r1:r1+corner_len, c2-th:c2, 3) = ret_b;
    display_frame(r2-th:r2, c1:c1+corner_len, 1) = ret_r; display_frame(r2-th:r2, c1:c1+corner_len, 2) = ret_g; display_frame(r2-th:r2, c1:c1+corner_len, 3) = ret_b;
    display_frame(r2-corner_len:r2, c1:c1+th, 1) = ret_r; display_frame(r2-corner_len:r2, c1:c1+th, 2) = ret_g; display_frame(r2-corner_len:r2, c1:c1+th, 3) = ret_b;
    display_frame(r2-th:r2, c2-corner_len:c2, 1) = ret_r; display_frame(r2-th:r2, c2-corner_len:c2, 2) = ret_g; display_frame(r2-th:r2, c2-corner_len:c2, 3) = ret_b;
    display_frame(r2-corner_len:r2, c2-th:c2, 1) = ret_r; display_frame(r2-corner_len:r2, c2-th:c2, 2) = ret_g; display_frame(r2-corner_len:r2, c2-th:c2, 3) = ret_b;
    
    % Status Banner
    banner_height = 36;
    if alarm_active
        ban_r = uint8(220); ban_g = uint8(20);  ban_b = uint8(30);
        status_text = '🚨 CRITICAL DROWSINESS: EYES CLOSED! WAKE UP!';
    elseif closed_counter > 2
        ban_r = uint8(220); ban_g = uint8(140); ban_b = uint8(20);
        status_text = sprintf('CAUTION: EYE CLOSURE DETECTED [%d/%d]', closed_counter, consec_trigger_limit);
    else
        ban_r = uint8(20);  ban_g = uint8(160); ban_b = uint8(80);
        status_text = sprintf('EYES: OPEN (Delta: %+2.0f%%)', edge_delta_pct);
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
        title(ax, sprintf('[%s] %s  |  Edges: %.1f / %.1f  |  FPS: %.1f', ...
              srcTag, status_text, curr_edges, baseline_edges, avg_fps), ...
              'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
        drawnow limitrate;
    catch
        break;
    end
    
    if useVideo
        pause(max(0.01, (1/30) - loop_time));
    end
end

fprintf('\n[STOP] Eye detection stopped cleanly.\n');

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
