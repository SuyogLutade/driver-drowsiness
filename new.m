clear all;
clc

disp('=== Eye Drowsiness Detection (Edge-Density Method) ===');
disp('Connecting to webcam...');
cam = webcam;
pause(2);

disp('>>> SIT STILL. EYES WIDE OPEN. Taking 5 reference frames... <<<');
pause(2);

[H, W, ~] = size(snapshot(cam));

% Eye region: upper-middle of frame where eyes typically are
row1 = round(H * 0.28); row2 = round(H * 0.56);
col1 = round(W * 0.15); col2 = round(W * 0.85);

% Average baseline over 5 frames for stability
baseline_edges = 0;
for k = 1:5
    fr = double(rgb2gray(snapshot(cam)));
    eye_patch = fr(row1:row2, col1:col2);
    [Gx, Gy] = gradient(eye_patch);
    baseline_edges = baseline_edges + mean(sqrt(Gx(:).^2 + Gy(:).^2));
    pause(0.15);
end
baseline_edges = baseline_edges / 5;

disp(['Baseline edge density (eyes open): ', num2str(round(baseline_edges,2))]);
disp('>>> Detection live! Close eyes ~1 second to trigger alarm. <<<');
disp('Close figure window to stop.');

closed_counter = 0;
f = figure;

while ishandle(f)
    frame = snapshot(cam);
    gray  = double(rgb2gray(frame));
    patch = gray(row1:row2, col1:col2);

    [Gx, Gy] = gradient(patch);
    curr_edges = mean(sqrt(Gx(:).^2 + Gy(:).^2));

    % Eyes CLOSED = edge density drops below 65% of baseline
    if curr_edges < baseline_edges * 0.65
        closed_counter = closed_counter + 1;
    else
        closed_counter = 0; % Eyes open -> reset immediately
    end

    disp(['Edge density: ', num2str(round(curr_edges,1)), ...
          ' / Baseline: ', num2str(round(baseline_edges,1)), ...
          ' | Closed frames: ', num2str(closed_counter), '/7']);

    % 7 consecutive closed frames (~0.7 sec) -> ALARM
    if closed_counter >= 7
        disp('!!! DROWSINESS DETECTED - WAKE UP !!!');
        fs = 8000;
        t_a = 0:1/fs:0.4;
        tone = sin(2*pi*880*t_a);
        sound([tone tone tone], fs);
        closed_counter = 0;
    end

    try
        figure(f);
        imshow(frame);
        title(['Edges: ', num2str(round(curr_edges,1)), ...
               ' | Baseline: ', num2str(round(baseline_edges,1)), ...
               ' | Closed: ', num2str(closed_counter), '/7']);
        drawnow;
    catch
        break;
    end

    pause(0.1);
end

disp('Stopped. Camera released.');
clear cam;
