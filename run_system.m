% =========================================================================
%  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
%  MASTER SYSTEM LAUNCHER
% =========================================================================
%  One-stop entry point to launch the GUI Dashboard, individual modules,
%  hardware diagnostics, or the interactive web presentation.
% =========================================================================

clear;
clc;
close all;

fprintf('========================================================================\n');
fprintf('   🚨 INTELLIGENT DRIVER DROWSINESS DETECTION & SAFETY SYSTEM\n');
fprintf('   Indian Institute of Information Technology, Allahabad\n');
fprintf('========================================================================\n\n');

fprintf('Available Operational Modules:\n');
fprintf('  [1] 🖥️  Launch Interactive GUI Dashboard (Recommended)\n');
fprintf('  [2] 👁️  Run Module 1: Eye Closure Detection (Edge-Density)\n');
fprintf('  [3] 🤦  Run Module 2: Head Lowering Detection (YCbCr Skin Segmentation)\n');
fprintf('  [4] 🌐  Open Web Presentation & Live Browser Dashboard\n');
fprintf('  [5] 🔧  Run Camera Hardware Diagnostic Check\n');
fprintf('  [0] ❌  Exit\n\n');

choice = input('Select an option (0-5) [Default = 1]: ', 's');
if isempty(choice)
    choice = '1';
end

switch strtrim(choice)
    case '1'
        fprintf('\n>>> Launching Interactive GUI Dashboard (DriverSafetyGUI)...\n');
        DriverSafetyGUI();
        
    case '2'
        fprintf('\n>>> Launching Module 1: Eye Closure Detection (new.m)...\n');
        new();
        
    case '3'
        fprintf('\n>>> Launching Module 2: Head Lowering Detection (HeadLowering.m)...\n');
        HeadLowering();
        
    case '4'
        fprintf('\n>>> Opening Web Presentation Dashboard in default browser...\n');
        webPath = fullfile(pwd, 'web_dashboard', 'index.html');
        if exist(webPath, 'file')
            web(webPath, '-browser');
            fprintf('Dashboard opened: %s\n', webPath);
        else
            fprintf('Web dashboard file not found at: %s\n', webPath);
        end
        
    case '5'
        fprintf('\n>>> Running Camera Hardware Diagnostic Check...\n');
        runHardwareDiagnostics();
        
    case '0'
        fprintf('\nExiting Driver Drowsiness System. Drive safely!\n');
        
    otherwise
        fprintf('\nInvalid choice. Launching default GUI Dashboard...\n');
        DriverSafetyGUI();
end

% -------------------------------------------------------------------------
% HARDWARE DIAGNOSTICS FUNCTION
% -------------------------------------------------------------------------
function runHardwareDiagnostics()
    fprintf('1. Querying installed webcams...\n');
    try
        camList = webcamlist;
        fprintf('   Found %d camera(s):\n', length(camList));
        for i = 1:length(camList)
            fprintf('   [%d] %s\n', i, camList{i});
        end
        
        fprintf('2. Initializing default camera test...\n');
        try evalin('base', 'clear cam'); catch; end
        cam = webcam(1);
        pause(1.2);
        testFrame = snapshot(cam);
        [H, W, C] = size(testFrame);
        fprintf('   Camera Resolution: %d x %d pixels (Channels: %d)\n', W, H, C);
        
        % Check lighting level
        gray = rgb2gray(testFrame);
        avgLuma = mean(gray(:));
        fprintf('   Average Frame Luminance: %.1f / 255\n', avgLuma);
        if avgLuma < 50
            fprintf('   ⚠️  WARNING: Lighting is dim. Increase room lighting for optimal detection.\n');
        elseif avgLuma > 220
            fprintf('   ⚠️  WARNING: Lighting is overexposed. Reduce direct glare.\n');
        else
            fprintf('   ✓ Lighting level is optimal for facial analysis.\n');
        end
        
        clear cam;
        fprintf('3. Camera released. Hardware is 100%% operational!\n');
    catch ME
        fprintf('   ❌ Hardware diagnostic failed: %s\n', ME.message);
    end
end
