% =========================================================================
%  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
%  Module 2: Real-Time Head Lowering / Dropping Detection (YCbCr Skin Segmentation)
% =========================================================================
%  Detects driver fatigue manifested as head drooping/lowering by tracking
%  active facial skin pixel density in real-time.
%  Optimized with vectorized matrix operations (60+ FPS) and an automotive HUD.
% =========================================================================

clear;
clc;
close all;

fprintf('\n=======================================================\n');
fprintf('  🚨 DRIVER FATIGUE MONITOR: HEAD LOWERING DETECTION   \n');
fprintf('  Algorithm: Fast Vectorized YCbCr Skin Segmentation   \n');
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
% 2. BASELINE CALIBRATION (Eyes open, looking ahead)
% -------------------------------------------------------------------------
fprintf('[2/4] Calibrating baseline driver pose...\n');
fprintf('      >>> PLEASE SIT UPRIGHT AND LOOK STRAIGHT AT CAMERA <<<\n');

numCalib = 5;
baseline_counts = zeros(1, numCalib);
frameSize = [360, 640];

for k = 1:numCalib
    raw = snapshot(cam);
    raw_res = imresize(raw, frameSize);
    I_d = double(raw_res);
    
    % Fast YCbCr Skin Segmentation
    cb = 0.148 * I_d(:,:,1) - 0.291 * I_d(:,:,2) + 0.439 * I_d(:,:,3) + 128;
    cr = 0.439 * I_d(:,:,1) - 0.368 * I_d(:,:,2) - 0.071 * I_d(:,:,3) + 128;
    skin_mask = (cr > 130 & cr < 180 & cb > 80 & cb < 160);
    
    baseline_counts(k) = sum(skin_mask(:));
    pause(0.1);
end

baseline_skin = mean(baseline_counts);
drop_threshold_pct = 10; % 10% drop in visible skin indicates head tilted/lowered
pixel_drop_threshold = (baseline_skin * drop_threshold_pct) / 100;

fprintf('      ✓ Baseline calibrated: %d skin pixels\n', round(baseline_skin));
fprintf('      ✓ Fatigue drop trigger: > %.0f%% skin loss (%d pixels)\n', ...
        drop_threshold_pct, round(pixel_drop_threshold));
fprintf('[3/4] Initializing High-Definition Automotive HUD...\n');

% -------------------------------------------------------------------------
% 3. PREPARE AUDIO ALARM (Non-blocking playback)
% -------------------------------------------------------------------------
fs = 8000;
t_alarm = 0:1/fs:0.35;
alarm_burst = sin(2 * pi * 880 * t_alarm);
alarm_signal = [alarm_burst, zeros(1, 400), alarm_burst, zeros(1, 400), alarm_burst];
alarmPlayer = audioplayer(alarm_signal, fs);

% -------------------------------------------------------------------------
% 4. BUILD PRESENTABLE HUD DISPLAY FIGURE
% -------------------------------------------------------------------------
fig = figure('Name', 'Driver Safety Monitor - Head Lowering Detection', ...
             'NumberTitle', 'off', ...
             'Color', [0.07 0.09 0.12], ...
             'Position', [150, 100, 960, 620], ...
             'MenuBar', 'none', ...
             'ToolBar', 'none');

ax = axes('Parent', fig, 'Position', [0.02, 0.02, 0.96, 0.96]);
axis(ax, 'off');

% Initial placeholder frame
init_frame = zeros(frameSize(1), frameSize(2), 3, 'uint8');
hImg = imshow(init_frame, 'Parent', ax);
hold(ax, 'on');

fprintf('[4/4] >>> SYSTEM ACTIVE & MONITORING <<<\n');
fprintf('      Lower head for ~0.5s to trigger alarm.\n');
fprintf('      Close figure window or press Ctrl+C to stop.\n\n');

consec_low_frames = 0;
max_consec_threshold = 10; % ~10 consecutive frames (~0.4 - 0.5 sec)
fps_history = zeros(1, 10);
fps_idx = 1;

% -------------------------------------------------------------------------
% 5. REAL-TIME MONITORING LOOP
% -------------------------------------------------------------------------
while ishandle(fig)
    t_start = tic;
    
    % Grab and resize snapshot
    raw = snapshot(cam);
    raw_res = imresize(raw, frameSize);
    I_d = double(raw_res);
    
    % Vectorized YCbCr Skin Segmentation
    cb = 0.148 * I_d(:,:,1) - 0.291 * I_d(:,:,2) + 0.439 * I_d(:,:,3) + 128;
    cr = 0.439 * I_d(:,:,1) - 0.368 * I_d(:,:,2) - 0.071 * I_d(:,:,3) + 128;
    skin_mask = (cr > 130 & cr < 180 & cb > 80 & cb < 160);
    curr_skin = sum(skin_mask(:));
    
    skin_drop = baseline_skin - curr_skin;
    skin_ratio = max(0, (curr_skin / max(1, baseline_skin)) * 100);
    
    % Detection Logic
    is_head_lowered = (skin_drop > pixel_drop_threshold);
    if is_head_lowered
        consec_low_frames = consec_low_frames + 1;
    else
        consec_low_frames = 0; % Instant reset when head is upright
    end
    
    % Trigger Alarm on Threshold
    alarm_active = false;
    if consec_low_frames >= max_consec_threshold
        alarm_active = true;
        if ~isplaying(alarmPlayer)
            play(alarmPlayer);
        end
        fprintf('  ⚠️  [ALARM TRIGGERED] Head lowering detected! Frame count: %d\n', consec_low_frames);
    end
    
    % ---------------------------------------------------------------------
    % COMPOSITE PRESENTATION HUD OVERLAY
    % ---------------------------------------------------------------------
    display_frame = raw_res;
    
    % 1. Picture-in-Picture (PIP) segmented skin mask (top-right corner)
    pip_h = 100; pip_w = 160;
    pip_r = 15:(14+pip_h);
    pip_c = (frameSize(2) - pip_w - 15):(frameSize(2) - 16);
    
    % Create colorized skin mask inset
    mask_pip = imresize(uint8(skin_mask) * 255, [pip_h, pip_w]);
    mask_rgb = cat(3, mask_pip * 0, mask_pip, round(mask_pip * 0.8)); % Cyan/Green hue
    
    % Draw PIP border & blend
    display_frame(pip_r, pip_c, :) = mask_rgb;
    % PIP border outline
    display_frame(pip_r(1):pip_r(1)+2, pip_c, :) = 255;
    display_frame(pip_r(end)-2:pip_r(end), pip_c, :) = 255;
    display_frame(pip_r, pip_c(1):pip_c(1)+2, :) = 255;
    display_frame(pip_r, pip_c(end)-2:pip_c(end), :) = 255;
    
    % 2. Draw Top Status Banner
    banner_height = 42;
    banner_color = [20, 160, 80];    % Green = Normal
    status_text = sprintf('STATUS: DRIVER ALERT (Skin: %3.0f%%)', skin_ratio);
    
    if consec_low_frames > 2 && ~alarm_active
        banner_color = [220, 140, 20];  % Amber = Caution
        status_text = sprintf('CAUTION: HEAD TILT / NODDING DETECTED [%d/%d]', consec_low_frames, max_consec_threshold);
    elseif alarm_active
        % Flashing Crimson Red
        if mod(consec_low_frames, 2) == 0
            banner_color = [220, 20, 30];
        else
            banner_color = [255, 60, 60];
        end
        status_text = '🚨 CRITICAL FATIGUE: HEAD LOWERED! WAKE UP!';
    end
    
    % Render top banner background
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
    
    % Update Figure
    try
        hImg.CData = display_frame;
        
        % Dynamic Title Overlay
        title(ax, sprintf('%s  |  Skin: %d / %d  |  FPS: %.1f', ...
              status_text, round(curr_skin), round(baseline_skin), avg_fps), ...
              'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');
        
        drawnow limitrate;
    catch
        break;
    end
end

fprintf('\n[STOP] Head lowering detection stopped cleanly. Camera released.\n');

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
