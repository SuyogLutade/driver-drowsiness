% =========================================================================
%  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
%  Module 1: Real-Time Eye Drowsiness Detection (Edge-Density Method)
% =========================================================================
%  Detects driver fatigue manifested as prolonged eye closure by analyzing
%  gradient magnitude (edge-density) across the eye region in real-time.
%  Optimized with adaptive ROI tracking, automotive HUD, and zero-flicker display.
% =========================================================================

clear;
clc;
close all;

fprintf('\n=======================================================\n');
fprintf('  👁️ DRIVER FATIGUE MONITOR: EYE CLOSURE DETECTION    \n');
fprintf('  Algorithm: Gradient Magnitude Edge-Density Analysis \n');
fprintf('=======================================================\n\n');

% -------------------------------------------------------------------------
% 1. WEBCAM INITIALIZATION & SAFE CLEANUP
% -------------------------------------------------------------------------
fprintf('[1/4] Initializing camera connection...\n');
try
    cam = webcam;
catch ME
    error('Could not connect to webcam. Verify camera is plugged in: %s', ME.message);
end

% Guarantee camera release on any exit/error/Ctrl+C
cleanupObj = onCleanup(@() safeCleanup(cam));

pause(1.5); % Camera auto-exposure stabilization

% -------------------------------------------------------------------------
% 2. CASCADE DETECTOR FOR ADAPTIVE FACE & EYE TRACKING
% -------------------------------------------------------------------------
useCascade = false;
try
    faceDetector = vision.CascadeObjectDetector('FrontalFaceCART');
    useCascade = true;
    fprintf('[2/4] Vision Cascade Detector loaded for adaptive tracking.\n');
catch
    fprintf('[2/4] Cascade detector not available; using calibrated geometric ROI.\n');
end

% -------------------------------------------------------------------------
% 3. BASELINE CALIBRATION (Eyes wide open, looking ahead)
% -------------------------------------------------------------------------
fprintf('[3/4] Calibrating driver baseline (eyes open)...\n');
fprintf('      >>> PLEASE SIT STILL WITH EYES WIDE OPEN <<<\n');

sampleFrame = snapshot(cam);
[H, W, ~] = size(sampleFrame);

% Default calibrated eye region (upper-middle of frame)
default_row1 = round(H * 0.28); default_row2 = round(H * 0.56);
default_col1 = round(W * 0.15); default_col2 = round(W * 0.85);

baseline_edges = 0;
numCalib = 5;

for k = 1:numCalib
    raw = snapshot(cam);
    gray = double(rgb2gray(raw));
    
    % Adaptive ROI search
    eye_roi = [default_row1, default_row2, default_col1, default_col2];
    if useCascade
        bboxes = faceDetector(raw);
        if ~isempty(bboxes)
            % Use largest detected face
            [~, maxIdx] = max(bboxes(:, 3) .* bboxes(:, 4));
            fb = bboxes(maxIdx, :);
            r1 = max(1, round(fb(2) + fb(4) * 0.20));
            r2 = min(H, round(fb(2) + fb(4) * 0.55));
            c1 = max(1, round(fb(1) + fb(3) * 0.10));
            c2 = min(W, round(fb(1) + fb(3) * 0.90));
            if (r2 - r1 > 20) && (c2 - c1 > 30)
                eye_roi = [r1, r2, c1, c2];
            end
        end
    end
    
    patch = gray(eye_roi(1):eye_roi(2), eye_roi(3):eye_roi(4));
    [Gx, Gy] = gradient(patch);
    baseline_edges = baseline_edges + mean(sqrt(Gx(:).^2 + Gy(:).^2));
    pause(0.15);
end

baseline_edges = baseline_edges / numCalib;
fprintf('      ✓ Baseline Edge Density (Eyes Open): %.2f\n', baseline_edges);
fprintf('      ✓ Drowsiness Trigger: < 65%% of baseline (%.2f)\n', baseline_edges * 0.65);
fprintf('[4/4] Launching High-Definition Automotive HUD...\n');

% -------------------------------------------------------------------------
% 4. PREPARE AUDIO ALARM (Non-blocking playback)
% -------------------------------------------------------------------------
fs = 8000;
t_alarm = 0:1/fs:0.35;
alarm_burst = sin(2 * pi * 880 * t_alarm);
alarm_signal = [alarm_burst, zeros(1, 400), alarm_burst, zeros(1, 400), alarm_burst];
alarmPlayer = audioplayer(alarm_signal, fs);

% -------------------------------------------------------------------------
% 5. BUILD PRESENTABLE HUD DISPLAY FIGURE
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

fprintf('\n>>> SYSTEM ACTIVE & MONITORING <<<\n');
fprintf('Close eyes for ~0.7s to trigger drowsiness alarm.\n');
fprintf('Close figure window or press Ctrl+C to stop.\n\n');

closed_counter = 0;
consec_trigger_limit = 7; % ~0.7s consecutive closed frames
fps_history = zeros(1, 10);
fps_idx = 1;
curr_eye_roi = [default_row1, default_row2, default_col1, default_col2];

% -------------------------------------------------------------------------
% 6. REAL-TIME MONITORING LOOP
% -------------------------------------------------------------------------
while ishandle(fig)
    t_start = tic;
    
    raw = snapshot(cam);
    gray = double(rgb2gray(raw));
    
    % Adaptive or fallback ROI tracking
    if useCascade
        bboxes = faceDetector(raw);
        if ~isempty(bboxes)
            [~, maxIdx] = max(bboxes(:, 3) .* bboxes(:, 4));
            fb = bboxes(maxIdx, :);
            r1 = max(1, round(fb(2) + fb(4) * 0.20));
            r2 = min(H, round(fb(2) + fb(4) * 0.55));
            c1 = max(1, round(fb(1) + fb(3) * 0.10));
            c2 = min(W, round(fb(1) + fb(3) * 0.90));
            if (r2 - r1 > 20) && (c2 - c1 > 30)
                % Smooth ROI transition (damping jitter)
                curr_eye_roi = round(curr_eye_roi * 0.4 + [r1, r2, c1, c2] * 0.6);
            end
        end
    end
    
    % Crop Eye Patch & Compute Edge Density
    r1 = curr_eye_roi(1); r2 = curr_eye_roi(2);
    c1 = curr_eye_roi(3); c2 = curr_eye_roi(4);
    
    patch = gray(r1:r2, c1:c2);
    [Gx, Gy] = gradient(patch);
    curr_edges = mean(sqrt(Gx(:).^2 + Gy(:).^2));
    
    % Detection Logic: Eyes closed if edge density drops below 65% of baseline
    is_eyes_closed = (curr_edges < baseline_edges * 0.65);
    
    if is_eyes_closed
        closed_counter = closed_counter + 1;
    else
        closed_counter = 0; % Instant reset when eyes open
    end
    
    % Alarm Condition
    alarm_active = false;
    if closed_counter >= consec_trigger_limit
        alarm_active = true;
        if ~isplaying(alarmPlayer)
            play(alarmPlayer);
        end
        fprintf('  ⚠️  [ALARM TRIGGERED] Prolonged eye closure! Frame count: %d\n', closed_counter);
    end
    
    % ---------------------------------------------------------------------
    % COMPOSITE PRESENTATION HUD OVERLAY
    % ---------------------------------------------------------------------
    display_frame = raw;
    edge_ratio = max(0, (curr_edges / max(0.1, baseline_edges)) * 100);
    
    % 1. Draw Eye Region Reticle / Target Box
    reticle_color = [50, 220, 100];   % Green = Open
    if closed_counter > 2 && ~alarm_active
        reticle_color = [240, 160, 20]; % Amber = Caution
    elseif alarm_active
        reticle_color = [255, 30, 30];  % Red = Drowsy
    end
    
    % Draw Reticle Corners
    corner_len = min(25, round((c2 - c1) * 0.15));
    th = 3; % Line thickness
    % Top-left
    display_frame(r1:r1+th, c1:c1+corner_len, 1) = reticle_color(1);
    display_frame(r1:r1+th, c1:c1+corner_len, 2) = reticle_color(2);
    display_frame(r1:r1+th, c1:c1+corner_len, 3) = reticle_color(3);
    display_frame(r1:r1+corner_len, c1:c1+th, 1) = reticle_color(1);
    display_frame(r1:r1+corner_len, c1:c1+th, 2) = reticle_color(2);
    display_frame(r1:r1+corner_len, c1:c1+th, 3) = reticle_color(3);
    % Top-right
    display_frame(r1:r1+th, c2-corner_len:c2, 1) = reticle_color(1);
    display_frame(r1:r1+th, c2-corner_len:c2, 2) = reticle_color(2);
    display_frame(r1:r1+th, c2-corner_len:c2, 3) = reticle_color(3);
    display_frame(r1:r1+corner_len, c2-th:c2, 1) = reticle_color(1);
    display_frame(r1:r1+corner_len, c2-th:c2, 2) = reticle_color(2);
    display_frame(r1:r1+corner_len, c2-th:c2, 3) = reticle_color(3);
    % Bottom-left
    display_frame(r2-th:r2, c1:c1+corner_len, 1) = reticle_color(1);
    display_frame(r2-th:r2, c1:c1+corner_len, 2) = reticle_color(2);
    display_frame(r2-th:r2, c1:c1+corner_len, 3) = reticle_color(3);
    display_frame(r2-corner_len:r2, c1:c1+th, 1) = reticle_color(1);
    display_frame(r2-corner_len:r2, c1:c1+th, 2) = reticle_color(2);
    display_frame(r2-corner_len:r2, c1:c1+th, 3) = reticle_color(3);
    % Bottom-right
    display_frame(r2-th:r2, c2-corner_len:c2, 1) = reticle_color(1);
    display_frame(r2-th:r2, c2-corner_len:c2, 2) = reticle_color(2);
    display_frame(r2-th:r2, c2-corner_len:c2, 3) = reticle_color(3);
    display_frame(r2-corner_len:r2, c2-th:c2, 1) = reticle_color(1);
    display_frame(r2-corner_len:r2, c2-th:c2, 2) = reticle_color(2);
    display_frame(r2-corner_len:r2, c2-th:c2, 3) = reticle_color(3);
    
    % 2. Draw Top Status Banner
    banner_height = 42;
    banner_color = [20, 160, 80];
    status_text = sprintf('EYES: OPEN (Edge Density: %3.0f%%)', edge_ratio);
    
    if closed_counter > 2 && ~alarm_active
        banner_color = [220, 140, 20];
        status_text = sprintf('CAUTION: EYE CLOSURE DETECTED [%d/%d]', closed_counter, consec_trigger_limit);
    elseif alarm_active
        if mod(closed_counter, 2) == 0
            banner_color = [220, 20, 30];
        else
            banner_color = [255, 60, 60];
        end
        status_text = '🚨 CRITICAL DROWSINESS: WAKE UP! 🚨';
    end
    
    for c = 1:3
        display_frame(1:banner_height, :, c) = banner_color(c);
    end
    
    % 3. Bottom Diagnostics Strip
    bottom_height = 36;
    for c = 1:3
        display_frame(end-bottom_height:end, :, c) = uint8(display_frame(end-bottom_height:end, :, c) * 0.25);
    end
    
    % Compute FPS
    loop_time = toc(t_start);
    fps = 1 / max(0.001, loop_time);
    fps_history(fps_idx) = fps;
    fps_idx = mod(fps_idx, 10) + 1;
    avg_fps = mean(fps_history(fps_history > 0));
    
    % Update Display
    try
        hImg.CData = display_frame;
        
        title(ax, sprintf('%s  |  Edges: %.1f / %.1f  |  FPS: %.1f', ...
              status_text, curr_edges, baseline_edges, avg_fps), ...
              'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');
        
        drawnow limitrate;
    catch
        break;
    end
end

fprintf('\n[STOP] Eye detection stopped cleanly. Camera released.\n');

% -------------------------------------------------------------------------
% HELPER CLEANUP FUNCTION
% -------------------------------------------------------------------------
function safeCleanup(~)
    try
        evalin('base', 'clear cam');
        fprintf('Camera released successfully.\n');
    catch
    end
end
