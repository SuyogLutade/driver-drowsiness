function DriverSafetyGUI()
% =========================================================================
%  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
%  Interactive Graphical User Interface & Telematics Dashboard
% =========================================================================
%  Combines Edge-Density Eye Closure Detection and YCbCr Skin Segmentation
%  into a unified real-time driver safety monitoring system.
%  Features adaptive baseline calibration, multi-metric head pose tracking,
%  and leaky accumulator counters for zero false-positive fatigue alerting.
% =========================================================================

    % Clean environment
    clc;
    close all;

    % App State Structure
    appData = struct();
    appData.isRunning = false;
    appData.cam = [];
    appData.vr = [];
    appData.useVideo = false;
    appData.soundEnabled = true;
    appData.mode = 1;         % 1: Dual Fusion, 2: Eye Only, 3: Head Only
    appData.sourceChoice = 1; % 1: Auto, 2: Webcam, 3: Eyes Video, 4: Head Video
    
    % Calibration Parameters
    appData.baselineEdges = 10.0;
    appData.baselineSkin = 25000;
    appData.baselineY = 160.0;
    appData.baselineUpper = 10000;
    appData.ySplit = 160;
    
    % Detection Thresholds (Responsive & Calibrated)
    appData.eyeSensitivityPct = 90;     % Edge trigger (% of baseline, 90% = -10% drop)
    appData.headShiftThreshold = 5.5;   % Downward centroid shift (px)
    appData.upperDropThresholdPct = 12; % Upper-face skin loss (%)
    
    % Leaky Accumulator Counters
    appData.eyeClosedFrames = 0;
    appData.headLoweredFrames = 0;
    appData.fatigueScore = 0; % 0 - 100%
    appData.totalFrames = 0;
    appData.incidentCount = 0;
    
    % Focused Eye ROI Initial Coordinates
    appData.r1 = 140; appData.r2 = 220;
    appData.c1 = 160; appData.c2 = 480;
    
    % Prepare Audio Alarm
    fs = 8000;
    t_alarm = 0:1/fs:0.35;
    burst = sin(2 * pi * 880 * t_alarm);
    alarm_signal = [burst, zeros(1, 400), burst, zeros(1, 400), burst];
    appData.alarmPlayer = audioplayer(alarm_signal, fs);
    
    % Cascade face detector if available
    appData.faceDetector = [];
    try
        appData.faceDetector = vision.CascadeObjectDetector('FrontalFaceCART');
    catch
    end

    % ---------------------------------------------------------------------
    % BUILD MAIN WINDOW
    % ---------------------------------------------------------------------
    figW = 1200; figH = 750;
    screenSize = get(0, 'ScreenSize');
    posX = max(30, round((screenSize(3) - figW) / 2));
    posY = max(30, round((screenSize(4) - figH) / 2));
    
    fig = figure('Name', 'Intelligent Driver Drowsiness Detection System - Telematics Dashboard', ...
                 'NumberTitle', 'off', ...
                 'Color', [0.07, 0.09, 0.13], ...
                 'Position', [posX, posY, figW, figH], ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'none', ...
                 'CloseRequestFcn', @onCloseApp);

    % Top Header Banner
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', '🚨 INTELLIGENT DRIVER DROWSINESS & FATIGUE TELEMATICS SYSTEM', ...
              'BackgroundColor', [0.09, 0.12, 0.18], 'ForegroundColor', [0.2, 0.85, 1.0], ...
              'FontSize', 14, 'FontWeight', 'bold', ...
              'Position', [0, figH - 45, figW, 45]);

    % Main Camera Axes (Left Panel)
    axCam = axes('Parent', fig, 'Units', 'pixels', ...
                 'Position', [30, 160, 780, 520], ...
                 'Color', [0.03, 0.04, 0.06]);
    axis(axCam, 'off');
    
    % Blank initial display
    initImg = zeros(480, 640, 3, 'uint8');
    hDisplay = imshow(initImg, 'Parent', axCam);
    title(axCam, 'SYSTEM STANDBY - CLICK [START MONITORING] TO CONNECT CAMERA', ...
          'Color', [0.7, 0.8, 0.9], 'FontSize', 11, 'FontWeight', 'bold');

    % ---------------------------------------------------------------------
    % RIGHT TELEMETRY & METRICS PANEL
    % ---------------------------------------------------------------------
    panelX = 840; panelW = 330;
    
    % Panel Background
    uicontrol('Parent', fig, 'Style', 'text', 'String', '', ...
              'BackgroundColor', [0.10, 0.13, 0.19], ...
              'Position', [panelX, 160, panelW, 520]);
          
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'LIVE SAFETY TELEMETRY', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.4, 0.9, 1.0], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'Position', [panelX + 15, 640, panelW - 30, 25]);
          
    % 1. System Status Badge
    lblStatus = uicontrol('Parent', fig, 'Style', 'text', ...
                          'String', '● STANDBY', ...
                          'BackgroundColor', [0.15, 0.20, 0.28], 'ForegroundColor', [0.7, 0.75, 0.85], ...
                          'FontSize', 12, 'FontWeight', 'bold', ...
                          'Position', [panelX + 20, 595, panelW - 40, 32]);

    % 2. Overall Fatigue Risk Level
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Overall Fatigue Danger Index:', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.8, 0.85, 0.9], ...
              'FontSize', 9, 'HorizontalAlignment', 'left', ...
              'Position', [panelX + 20, 560, panelW - 40, 18]);
          
    lblFatigue = uicontrol('Parent', fig, 'Style', 'text', ...
                           'String', '0 % (SAFE)', ...
                           'BackgroundColor', [0.08, 0.25, 0.15], 'ForegroundColor', [0.3, 1.0, 0.4], ...
                           'FontSize', 13, 'FontWeight', 'bold', ...
                           'Position', [panelX + 20, 525, panelW - 40, 30]);

    % 3. Module 1: Eye Edge Density
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Eye Gradient Density (Edges):', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.8, 0.85, 0.9], ...
              'FontSize', 9, 'HorizontalAlignment', 'left', ...
              'Position', [panelX + 20, 485, panelW - 40, 18]);
          
    lblEyeMetric = uicontrol('Parent', fig, 'Style', 'text', ...
                             'String', 'Current: -- / Baseline: --', ...
                             'BackgroundColor', [0.12, 0.16, 0.24], 'ForegroundColor', [0.9, 0.9, 0.9], ...
                             'FontSize', 10, ...
                             'Position', [panelX + 20, 455, panelW - 40, 25]);
                         
    lblEyeConsec = uicontrol('Parent', fig, 'Style', 'text', ...
                             'String', 'Eye Accumulator: 0 / 6 [Normal]', ...
                             'BackgroundColor', [0.12, 0.16, 0.24], 'ForegroundColor', [0.3, 0.9, 0.5], ...
                             'FontSize', 9, 'FontWeight', 'bold', ...
                             'Position', [panelX + 20, 425, panelW - 40, 22]);

    % 4. Module 2: Head Lowering Pose
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Head Pose (Centroid & Skin Shift):', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.8, 0.85, 0.9], ...
              'FontSize', 9, 'HorizontalAlignment', 'left', ...
              'Position', [panelX + 20, 385, panelW - 40, 18]);
          
    lblHeadMetric = uicontrol('Parent', fig, 'Style', 'text', ...
                              'String', 'Y-Shift: -- / Upper Drop: --', ...
                              'BackgroundColor', [0.12, 0.16, 0.24], 'ForegroundColor', [0.9, 0.9, 0.9], ...
                              'FontSize', 10, ...
                              'Position', [panelX + 20, 355, panelW - 40, 25]);
                          
    lblHeadConsec = uicontrol('Parent', fig, 'Style', 'text', ...
                              'String', 'Nod Accumulator: 0 / 6 [Normal]', ...
                              'BackgroundColor', [0.12, 0.16, 0.24], 'ForegroundColor', [0.3, 0.9, 0.5], ...
                              'FontSize', 9, 'FontWeight', 'bold', ...
                              'Position', [panelX + 20, 325, panelW - 40, 22]);

    % 5. Operational Telemetry (FPS, Incidents, Runtime)
    lblTelemetry = uicontrol('Parent', fig, 'Style', 'text', ...
                             'String', sprintf('FPS: 0.0   |   Incidents: 0\nWebcam: Ready   |   Alarms: 0'), ...
                             'BackgroundColor', [0.08, 0.10, 0.15], 'ForegroundColor', [0.7, 0.8, 0.95], ...
                             'FontSize', 9, ...
                             'Position', [panelX + 20, 250, panelW - 40, 50]);

    % Diagnostic Snapshot Button
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', '📸 Save Incident Snapshot', ...
              'BackgroundColor', [0.18, 0.25, 0.38], 'ForegroundColor', 'w', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'Position', [panelX + 20, 180, panelW - 40, 40], ...
              'Callback', @onSnapshot);

    % ---------------------------------------------------------------------
    % BOTTOM CONTROL BAR
    % ---------------------------------------------------------------------
    ctrlY = 15; ctrlH = 130;
    uicontrol('Parent', fig, 'Style', 'text', 'String', '', ...
              'BackgroundColor', [0.10, 0.13, 0.19], ...
              'Position', [30, ctrlY, figW - 60, ctrlH]);

    % Button: Start Monitoring
    btnStart = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
                         'String', '▶ START MONITORING', ...
                         'BackgroundColor', [0.15, 0.65, 0.30], 'ForegroundColor', 'w', ...
                         'FontSize', 11, 'FontWeight', 'bold', ...
                         'Position', [45, ctrlY + 70, 175, 45], ...
                         'Callback', @onStartStop);

    % Button: Calibrate
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', '🎯 Recalibrate Baseline', ...
              'BackgroundColor', [0.20, 0.45, 0.70], 'ForegroundColor', 'w', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'Position', [230, ctrlY + 70, 165, 45], ...
              'Callback', @onCalibrate);

    % Detection Algorithm Mode Selector
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Detection Mode:', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.8, 0.85, 0.9], ...
              'FontSize', 8, 'HorizontalAlignment', 'left', ...
              'Position', [405, ctrlY + 95, 140, 16]);
          
    popMode = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
                        'String', {'Dual Fusion (Eyes + Head)', 'Eye Closure Only', 'Head Lowering Only'}, ...
                        'BackgroundColor', [0.15, 0.20, 0.28], 'ForegroundColor', 'w', ...
                        'FontSize', 9, ...
                        'Position', [405, ctrlY + 70, 195, 25], ...
                        'Callback', @onModeChanged);

    % Video Source Selector
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Video Feed Source:', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.8, 0.85, 0.9], ...
              'FontSize', 8, 'HorizontalAlignment', 'left', ...
              'Position', [610, ctrlY + 95, 160, 16]);
          
    popSource = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
                          'String', {'Auto (Webcam with Fallback)', 'Live Webcam (DirectShow)', 'Dataset Eyes Video (e1.mp4)', 'Dataset Head Video (h1.mp4)'}, ...
                          'BackgroundColor', [0.15, 0.20, 0.28], 'ForegroundColor', 'w', ...
                          'FontSize', 9, ...
                          'Position', [610, ctrlY + 70, 220, 25], ...
                          'Callback', @onSourceChanged);

    % Audio Alarm Toggle
    btnAudio = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
                         'String', '🔊 Audio: ON', ...
                         'BackgroundColor', [0.25, 0.35, 0.45], 'ForegroundColor', 'w', ...
                         'FontSize', 9, 'FontWeight', 'bold', ...
                         'Position', [840, ctrlY + 70, 110, 45], ...
                         'Callback', @onToggleAudio);

    % Test Alarm Button
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', '🔔 Test Alarm', ...
              'BackgroundColor', [0.20, 0.25, 0.35], 'ForegroundColor', [0.8, 0.9, 1.0], ...
              'FontSize', 9, ...
              'Position', [960, ctrlY + 70, 100, 45], ...
              'Callback', @(~,~) play(appData.alarmPlayer));

    % Sliders: Sensitivity Configuration
    lblSldEye = uicontrol('Parent', fig, 'Style', 'text', ...
                          'String', 'Eye Trigger: 90% (-10% drop)', ...
                          'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.75, 0.8, 0.85], ...
                          'FontSize', 8, 'HorizontalAlignment', 'left', ...
                          'Position', [45, ctrlY + 36, 175, 16]);
    sldEye = uicontrol('Parent', fig, 'Style', 'slider', ...
                       'Min', 80, 'Max', 96, 'Value', 90, ...
                       'Position', [45, ctrlY + 14, 175, 20], ...
                       'Callback', @onSliderEye);

    lblSldHead = uicontrol('Parent', fig, 'Style', 'text', ...
                           'String', 'Head Nod Shift: 5.5 px downward', ...
                           'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.75, 0.8, 0.85], ...
                           'FontSize', 8, 'HorizontalAlignment', 'left', ...
                           'Position', [230, ctrlY + 36, 175, 16]);
    sldHead = uicontrol('Parent', fig, 'Style', 'slider', ...
                        'Min', 3.0, 'Max', 15.0, 'Value', 5.5, ...
                        'Position', [230, ctrlY + 14, 165, 20], ...
                        'Callback', @onSliderHead);

    % Status Footer
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Adaptive Edge-Density & YCbCr Skin Segmentation | IIIT Allahabad Production Edition', ...
              'BackgroundColor', [0.10, 0.13, 0.19], 'ForegroundColor', [0.45, 0.50, 0.60], ...
              'FontSize', 8, 'HorizontalAlignment', 'left', ...
              'Position', [405, ctrlY + 16, 650, 20]);

    % Store handles inside figure guidata
    handles = struct('fig', fig, 'axCam', axCam, 'hDisplay', hDisplay, ...
                     'lblStatus', lblStatus, 'lblFatigue', lblFatigue, ...
                     'lblEyeMetric', lblEyeMetric, 'lblEyeConsec', lblEyeConsec, ...
                     'lblHeadMetric', lblHeadMetric, 'lblHeadConsec', lblHeadConsec, ...
                     'lblTelemetry', lblTelemetry, 'btnStart', btnStart, ...
                     'btnAudio', btnAudio, 'popMode', popMode, 'popSource', popSource, ...
                     'sldEye', sldEye, 'sldHead', sldHead, ...
                     'lblSldEye', lblSldEye, 'lblSldHead', lblSldHead);
    guidata(fig, handles);

    % ---------------------------------------------------------------------
    % CALLBACK FUNCTIONS
    % ---------------------------------------------------------------------
    function onStartStop(~, ~)
        if ~appData.isRunning
            startMonitoring();
        else
            stopMonitoring();
        end
    end

    function onSourceChanged(src, ~)
        appData.sourceChoice = get(src, 'Value');
        if appData.isRunning
            stopMonitoring();
            startMonitoring();
        end
    end

    function startMonitoring()
        set(handles.lblStatus, 'String', '⏳ INITIALIZING VIDEO SOURCE...', ...
            'BackgroundColor', [0.3, 0.25, 0.05], 'ForegroundColor', [1.0, 0.9, 0.2]);
        drawnow;
        
        projectDir = fileparts(mfilename('fullpath'));
        if isempty(projectDir), projectDir = pwd; end
        
        appData.useVideo = false;
        appData.vr = [];
        
        try evalin('base', 'clear cam'); catch; end
        
        choice = appData.sourceChoice;
        if choice == 3 % Force Dataset Eyes
            vPath = fullfile(projectDir, 'dbase', 'eyes', 'e1.mp4');
            if exist(vPath, 'file')
                appData.vr = VideoReader(vPath);
                appData.useVideo = true;
            end
        elseif choice == 4 % Force Dataset Head
            vPath = fullfile(projectDir, 'dbase', 'head', 'h1.mp4');
            if exist(vPath, 'file')
                appData.vr = VideoReader(vPath);
                appData.useVideo = true;
            end
        elseif choice == 2 % Force Live Webcam
            try
                appData.cam = webcam(1);
                pause(0.4);
                snapshot(appData.cam);
            catch ME
                errordlg(sprintf('Cannot connect to webcam: %s', ME.message), 'Webcam Error');
                set(handles.lblStatus, 'String', '❌ WEBCAM ERROR', ...
                    'BackgroundColor', [0.4, 0.1, 0.1], 'ForegroundColor', 'w');
                return;
            end
        else % Choice 1: Auto (Try webcam, fallback to video)
            try
                appData.cam = webcam(1);
                pause(0.4);
                snapshot(appData.cam);
            catch
                appData.useVideo = true;
                try clear('appData.cam'); catch; end
                appData.cam = [];
                
                if appData.mode == 3
                    vPath = fullfile(projectDir, 'dbase', 'head', 'h1.mp4');
                else
                    vPath = fullfile(projectDir, 'dbase', 'eyes', 'e1.mp4');
                end
                
                if exist(vPath, 'file')
                    appData.vr = VideoReader(vPath);
                else
                    errordlg('Webcam inaccessible and dataset video not found.', 'Source Error');
                    set(handles.lblStatus, 'String', '❌ SOURCE ERROR', ...
                        'BackgroundColor', [0.4, 0.1, 0.1], 'ForegroundColor', 'w');
                    return;
                end
            end
        end
        
        appData.isRunning = true;
        set(handles.btnStart, 'String', '⏹ STOP MONITORING', ...
            'BackgroundColor', [0.8, 0.2, 0.2]);
        
        % Auto Calibrate Baseline
        performCalibration();
        
        % Run Main Loop
        runMonitoringLoop();
    end

    function stopMonitoring()
        appData.isRunning = false;
        set(handles.btnStart, 'String', '▶ START MONITORING', ...
            'BackgroundColor', [0.15, 0.65, 0.30]);
        set(handles.lblStatus, 'String', '● STANDBY', ...
            'BackgroundColor', [0.15, 0.20, 0.28], 'ForegroundColor', [0.7, 0.75, 0.85]);
        set(handles.lblFatigue, 'String', '0 % (STANDBY)', ...
            'BackgroundColor', [0.15, 0.20, 0.28], 'ForegroundColor', [0.7, 0.75, 0.85]);
        
        if ~isempty(appData.cam)
            try clear('appData.cam'); catch; end
            appData.cam = [];
        end
        appData.vr = [];
    end

    function onCalibrate(~, ~)
        if appData.isRunning
            performCalibration();
        else
            msgbox('Start monitoring first to calibrate baseline.', 'Notice');
        end
    end

    function performCalibration()
        set(handles.lblStatus, 'String', '🎯 CALIBRATING BASELINE (LOOK FORWARD)', ...
            'BackgroundColor', [0.1, 0.3, 0.5], 'ForegroundColor', 'w');
        drawnow;
        
        if ~appData.useVideo
            sampleFrame = snapshot(appData.cam);
        else
            if ~hasFrame(appData.vr), appData.vr.CurrentTime = 0; end
            sampleFrame = readFrame(appData.vr);
        end
        [H, W, ~] = size(sampleFrame);
        
        % Focused eye band ROI
        appData.r1 = round(H * 0.31); appData.r2 = round(H * 0.45);
        appData.c1 = round(W * 0.26); appData.c2 = round(W * 0.74);
        
        % Try cascade face detector once during calibration
        if ~isempty(appData.faceDetector)
            try
                bboxes = appData.faceDetector(sampleFrame);
                if ~isempty(bboxes)
                    [~, mIdx] = max(bboxes(:, 3) .* bboxes(:, 4));
                    fb = bboxes(mIdx, :);
                    ar1 = max(1, round(fb(2) + fb(4) * 0.28));
                    ar2 = min(H, round(fb(2) + fb(4) * 0.45));
                    ac1 = max(1, round(fb(1) + fb(3) * 0.20));
                    ac2 = min(W, round(fb(1) + fb(3) * 0.80));
                    if (ar2 - ar1 > 15) && (ac2 - ac1 > 25)
                        appData.r1 = ar1; appData.r2 = ar2;
                        appData.c1 = ac1; appData.c2 = ac2;
                    end
                end
            catch
            end
        end
        
        edgeSum = 0; skinSum = 0; ySum = 0;
        nCal = 5;
        for c = 1:nCal
            if ~appData.useVideo
                f_raw = snapshot(appData.cam);
            else
                if ~hasFrame(appData.vr), appData.vr.CurrentTime = 0; end
                f_raw = readFrame(appData.vr);
            end
            
            % Eye Region
            gray = single(rgb2gray(f_raw));
            patch = gray(appData.r1:appData.r2, appData.c1:appData.c2);
            [Gx, Gy] = gradient(patch);
            edgeSum = edgeSum + mean(sqrt(Gx(:).^2 + Gy(:).^2));
            
            % Skin Region & Centroid
            f_small = single(f_raw(1:2:end, 1:2:end, :));
            cb = 0.148 * f_small(:,:,1) - 0.291 * f_small(:,:,2) + 0.439 * f_small(:,:,3) + 128;
            cr = 0.439 * f_small(:,:,1) - 0.368 * f_small(:,:,2) - 0.071 * f_small(:,:,3) + 128;
            mask = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
            skinSum = skinSum + sum(mask(:));
            [rows, ~] = find(mask);
            if ~isempty(rows)
                ySum = ySum + mean(rows);
            else
                ySum = ySum + size(f_small, 1) * 0.45;
            end
            pause(0.06);
        end
        
        appData.baselineEdges = max(0.5, edgeSum / nCal);
        appData.baselineSkin = max(100, skinSum / nCal);
        appData.baselineY = ySum / nCal;
        appData.ySplit = max(10, min(round(H / 2) - 10, round(appData.baselineY)));
        
        % Upper face baseline
        upperSum = 0;
        for c = 1:nCal
            if ~appData.useVideo, f_raw = snapshot(appData.cam); else, f_raw = readFrame(appData.vr); end
            f_small = single(f_raw(1:2:end, 1:2:end, :));
            cb = 0.148 * f_small(:,:,1) - 0.291 * f_small(:,:,2) + 0.439 * f_small(:,:,3) + 128;
            cr = 0.439 * f_small(:,:,1) - 0.368 * f_small(:,:,2) - 0.071 * f_small(:,:,3) + 128;
            mask = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
            upperSum = upperSum + sum(sum(mask(1:appData.ySplit, :)));
        end
        appData.baselineUpper = max(50, upperSum / nCal);
        
        set(handles.lblStatus, 'String', '✓ BASELINE CALIBRATED & ACTIVE', ...
            'BackgroundColor', [0.10, 0.40, 0.20], 'ForegroundColor', [0.4, 1.0, 0.5]);
        drawnow;
    end

    function onModeChanged(src, ~)
        appData.mode = get(src, 'Value');
    end

    function onToggleAudio(src, ~)
        appData.soundEnabled = ~appData.soundEnabled;
        if appData.soundEnabled
            set(src, 'String', '🔊 Audio: ON', 'BackgroundColor', [0.25, 0.35, 0.45]);
        else
            set(src, 'String', '🔇 Audio: OFF', 'BackgroundColor', [0.45, 0.25, 0.25]);
        end
    end

    function onSliderEye(src, ~)
        appData.eyeSensitivityPct = round(get(src, 'Value'));
        set(handles.lblSldEye, 'String', sprintf('Eye Trigger: %d%% (-%d%% drop)', ...
            appData.eyeSensitivityPct, 100 - appData.eyeSensitivityPct));
    end

    function onSliderHead(src, ~)
        appData.headShiftThreshold = get(src, 'Value');
        set(handles.lblSldHead, 'String', sprintf('Head Nod Shift: %.1f px downward', appData.headShiftThreshold));
    end

    function onSnapshot(~, ~)
        if appData.isRunning
            snap = get(handles.hDisplay, 'CData');
            ts = char(datetime("now", "Format", "uuuu-MM-dd_HH-mm-ss"));
            filename = sprintf('incident_snapshot_%s.jpg', ts);
            imwrite(snap, filename);
            appData.incidentCount = appData.incidentCount + 1;
            msgbox(sprintf('Diagnostic snapshot saved successfully:\n%s', filename), 'Snapshot Saved');
        else
            msgbox('System is not running. Start monitoring first.', 'Notice');
        end
    end

    function onCloseApp(~, ~)
        appData.isRunning = false;
        try
            if ~isempty(appData.cam)
                clear('appData.cam');
            end
        catch
        end
        delete(fig);
    end

    % ---------------------------------------------------------------------
    % MAIN REAL-TIME MONITORING WORKER
    % ---------------------------------------------------------------------
    function runMonitoringLoop()
        fpsHistory = zeros(1, 10);
        fpsIndex = 1;
        alarmCounter = 0;
        
        while appData.isRunning && ishandle(fig)
            tLoop = tic;
            
            % Grab Frame
            if ~appData.useVideo
                frame = snapshot(appData.cam);
            else
                if ~hasFrame(appData.vr), appData.vr.CurrentTime = 0; end
                frame = readFrame(appData.vr);
            end
            [H, W, ~] = size(frame);
            
            % 1. PROCESS EYE CLOSURE (MODULE 1) - Focused Eye Band
            r1 = max(1, min(H, appData.r1)); r2 = max(1, min(H, appData.r2));
            c1 = max(1, min(W, appData.c1)); c2 = max(1, min(W, appData.c2));
            
            gray = single(rgb2gray(frame));
            patch = gray(r1:r2, c1:c2);
            [Gx, Gy] = gradient(patch);
            currEdges = mean(sqrt(Gx(:).^2 + Gy(:).^2));
            edgeThreshold = appData.baselineEdges * (appData.eyeSensitivityPct / 100);
            
            isEyesClosed = (currEdges < edgeThreshold);
            % Leaky Accumulator for Eyes
            if isEyesClosed && (appData.mode == 1 || appData.mode == 2)
                appData.eyeClosedFrames = min(12, appData.eyeClosedFrames + 2);
            else
                appData.eyeClosedFrames = max(0, appData.eyeClosedFrames - 1);
            end
            
            % 2. PROCESS HEAD LOWERING (MODULE 2) - Multi-Metric Spatial Pose
            fSmall = single(frame(1:2:end, 1:2:end, :));
            cb = 0.148 * fSmall(:,:,1) - 0.291 * fSmall(:,:,2) + 0.439 * fSmall(:,:,3) + 128;
            cr = 0.439 * fSmall(:,:,1) - 0.368 * fSmall(:,:,2) - 0.071 * fSmall(:,:,3) + 128;
            skinMask = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
            currSkin = sum(skinMask(:));
            
            [rows, ~] = find(skinMask);
            if ~isempty(rows)
                currY = mean(rows);
            else
                currY = appData.baselineY + 30;
            end
            yShift = currY - appData.baselineY;
            
            ySplitBound = max(1, min(size(skinMask, 1), appData.ySplit));
            upperSkin = sum(sum(skinMask(1:ySplitBound, :)));
            upperDropPct = ((appData.baselineUpper - upperSkin) / max(1, appData.baselineUpper)) * 100;
            
            isHeadLowered = (yShift > appData.headShiftThreshold) || ...
                            (upperDropPct > appData.upperDropThresholdPct) || ...
                            (currSkin < appData.baselineSkin * 0.85);
            
            % Leaky Accumulator for Head Lowering
            if isHeadLowered && (appData.mode == 1 || appData.mode == 3)
                appData.headLoweredFrames = min(12, appData.headLoweredFrames + 2);
            else
                appData.headLoweredFrames = max(0, appData.headLoweredFrames - 1);
            end
            
            % 3. DANGER INDEX FUSION
            eyeDanger = min(100, (appData.eyeClosedFrames / 6) * 100);
            headDanger = min(100, (appData.headLoweredFrames / 6) * 100);
            
            if appData.mode == 1 % Dual Fusion
                appData.fatigueScore = round(max(eyeDanger, headDanger) * 0.7 + (eyeDanger * headDanger / 100) * 0.3);
            elseif appData.mode == 2 % Eye Only
                appData.fatigueScore = round(eyeDanger);
            else % Head Only
                appData.fatigueScore = round(headDanger);
            end
            
            % 4. TRIGGER ALARM
            isAlarm = (appData.eyeClosedFrames >= 6) || (appData.headLoweredFrames >= 6);
            if isAlarm
                alarmCounter = alarmCounter + 1;
                if appData.soundEnabled && ~isplaying(appData.alarmPlayer)
                    play(appData.alarmPlayer);
                end
            end
            
            % -------------------------------------------------------------
            % DRAW HUD GRAPHICS ONTO VIDEO FRAME
            % -------------------------------------------------------------
            displayFrame = frame;
            
            % Eye Reticle Overlay
            retColor = [50, 220, 100];
            if appData.eyeClosedFrames > 2 && ~isAlarm
                retColor = [240, 160, 20];
            elseif isAlarm
                retColor = [255, 30, 30];
            end
            
            cLen = min(30, round((c2 - c1) * 0.15));
            tTh = 3;
            % Top-Left
            displayFrame(r1:r1+tTh, c1:c1+cLen, 1) = retColor(1);
            displayFrame(r1:r1+tTh, c1:c1+cLen, 2) = retColor(2);
            displayFrame(r1:r1+tTh, c1:c1+cLen, 3) = retColor(3);
            displayFrame(r1:r1+cLen, c1:c1+tTh, 1) = retColor(1);
            displayFrame(r1:r1+cLen, c1:c1+tTh, 2) = retColor(2);
            displayFrame(r1:r1+cLen, c1:c1+tTh, 3) = retColor(3);
            % Top-Right
            displayFrame(r1:r1+tTh, c2-cLen:c2, 1) = retColor(1);
            displayFrame(r1:r1+tTh, c2-cLen:c2, 2) = retColor(2);
            displayFrame(r1:r1+tTh, c2-cLen:c2, 3) = retColor(3);
            displayFrame(r1:r1+cLen, c2-tTh:c2, 1) = retColor(1);
            displayFrame(r1:r1+cLen, c2-tTh:c2, 2) = retColor(2);
            displayFrame(r1:r1+cLen, c2-tTh:c2, 3) = retColor(3);
            % Bottom-Left
            displayFrame(r2-tTh:r2, c1:c1+cLen, 1) = retColor(1);
            displayFrame(r2-tTh:r2, c1:c1+cLen, 2) = retColor(2);
            displayFrame(r2-tTh:r2, c1:c1+cLen, 3) = retColor(3);
            displayFrame(r2-cLen:r2, c1:c1+tTh, 1) = retColor(1);
            displayFrame(r2-cLen:r2, c1:c1+tTh, 2) = retColor(2);
            displayFrame(r2-cLen:r2, c1:c1+tTh, 3) = retColor(3);
            % Bottom-Right
            displayFrame(r2-tTh:r2, c2-cLen:c2, 1) = retColor(1);
            displayFrame(r2-tTh:r2, c2-cLen:c2, 2) = retColor(2);
            displayFrame(r2-tTh:r2, c2-cLen:c2, 3) = retColor(3);
            displayFrame(r2-cLen:r2, c2-tTh:c2, 1) = retColor(1);
            displayFrame(r2-cLen:r2, c2-tTh:c2, 2) = retColor(2);
            displayFrame(r2-cLen:r2, c2-tTh:c2, 3) = retColor(3);
            
            % Fast Skin Mask PIP in top right
            pipH = 80; pipW = 120;
            maskPip = skinMask(1:2:min(end, 2*pipH), 1:2:min(end, 2*pipW));
            [pmh, pmw] = size(maskPip);
            pipR = 10:(9+pmh);
            pipC = (W - pmw - 10):(W - 11);
            maskUint = uint8(maskPip) * 220;
            displayFrame(pipR, pipC, 1) = uint8(0);
            displayFrame(pipR, pipC, 2) = maskUint;
            displayFrame(pipR, pipC, 3) = uint8(maskUint * 0.8);
            
            % Top HUD Status Banner
            bH = 38;
            bColor = [20, 160, 80];
            statusStr = 'ACTIVE: DRIVER FULLY ALERT';
            
            if (appData.eyeClosedFrames > 2 || appData.headLoweredFrames > 2) && ~isAlarm
                bColor = [220, 140, 20];
                statusStr = 'CAUTION: SIGNS OF FATIGUE DETECTED';
            elseif isAlarm
                if mod(alarmCounter, 2) == 0
                    bColor = [220, 20, 30];
                else
                    bColor = [255, 60, 60];
                end
                if appData.eyeClosedFrames >= 6
                    statusStr = '🚨 DROWSINESS: PROLONGED EYE CLOSURE! WAKE UP!';
                else
                    statusStr = '🚨 DROWSINESS: HEAD LOWERED / NOD OFF! WAKE UP!';
                end
            end
            
            for c = 1:3
                displayFrame(1:bH, :, c) = bColor(c);
            end
            
            % Render Display
            set(handles.hDisplay, 'CData', displayFrame);
            title(handles.axCam, statusStr, 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
            
            % Compute FPS
            loopSec = toc(tLoop);
            curFps = 1 / max(0.001, loopSec);
            fpsHistory(fpsIndex) = curFps;
            fpsIndex = mod(fpsIndex, 10) + 1;
            avgFps = mean(fpsHistory(fpsHistory > 0));
            appData.totalFrames = appData.totalFrames + 1;
            
            % Update Right Panel Controls
            if isAlarm
                set(handles.lblStatus, 'String', '🚨 CRITICAL FATIGUE ALARM!', ...
                    'BackgroundColor', [0.85, 0.10, 0.15], 'ForegroundColor', 'w');
                set(handles.lblFatigue, 'String', sprintf('%d %% (CRITICAL)', appData.fatigueScore), ...
                    'BackgroundColor', [0.7, 0.1, 0.1], 'ForegroundColor', 'w');
            elseif appData.fatigueScore > 35
                set(handles.lblStatus, 'String', '⚠️ CAUTION: FATIGUE ELEVATED', ...
                    'BackgroundColor', [0.75, 0.50, 0.05], 'ForegroundColor', 'w');
                set(handles.lblFatigue, 'String', sprintf('%d %% (ELEVATED)', appData.fatigueScore), ...
                    'BackgroundColor', [0.55, 0.35, 0.05], 'ForegroundColor', [1.0, 0.9, 0.3]);
            else
                set(handles.lblStatus, 'String', '✓ DRIVER ALERT (SAFE)', ...
                    'BackgroundColor', [0.10, 0.45, 0.20], 'ForegroundColor', [0.4, 1.0, 0.5]);
                set(handles.lblFatigue, 'String', sprintf('%d %% (NORMAL)', appData.fatigueScore), ...
                    'BackgroundColor', [0.08, 0.25, 0.15], 'ForegroundColor', [0.3, 1.0, 0.4]);
            end
            
            % Eye Metric Labels
            edgeDeltaPct = ((currEdges - appData.baselineEdges) / appData.baselineEdges) * 100;
            set(handles.lblEyeMetric, 'String', sprintf('Edges: %.1f | Base: %.1f (Δ %+.0f%%)', ...
                currEdges, appData.baselineEdges, edgeDeltaPct));
            if appData.eyeClosedFrames > 0
                set(handles.lblEyeConsec, 'String', sprintf('Closed Score: %d / 6 [Alert]', appData.eyeClosedFrames), ...
                    'ForegroundColor', [1.0, 0.4, 0.4]);
            else
                set(handles.lblEyeConsec, 'String', 'Eyes: Open [Stable]', ...
                    'ForegroundColor', [0.3, 0.9, 0.5]);
            end
            
            % Head Metric Labels
            set(handles.lblHeadMetric, 'String', sprintf('Shift: %+1.1f px | Upper: %+.0f%%', yShift, -upperDropPct));
            if appData.headLoweredFrames > 0
                set(handles.lblHeadConsec, 'String', sprintf('Nod Score: %d / 6 [Alert]', appData.headLoweredFrames), ...
                    'ForegroundColor', [1.0, 0.4, 0.4]);
            else
                set(handles.lblHeadConsec, 'String', 'Head Position: Upright', ...
                    'ForegroundColor', [0.3, 0.9, 0.5]);
            end
            
            % Telemetry
            srcName = 'Live Camera';
            if appData.useVideo, srcName = 'Dataset Video'; end
            set(handles.lblTelemetry, 'String', sprintf('FPS: %.1f   |   Source: %s\nAlarms: %d   |   Incidents: %d', ...
                avgFps, srcName, alarmCounter, appData.incidentCount));
            
            drawnow limitrate;
            if appData.useVideo
                pause(max(0.01, (1/30) - loopSec));
            end
        end
    end
end
