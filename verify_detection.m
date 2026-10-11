% End-to-End Detection Verification Script
fprintf('============================================\n');
fprintf(' DETECTION ALGORITHM VERIFICATION\n');
fprintf('============================================\n\n');

%% 1. EYE CLOSURE TEST
fprintf('=== TEST 1: EYE CLOSURE (dbase/eyes/e1.mp4) ===\n');
vr = VideoReader(fullfile(pwd, 'dbase', 'eyes', 'e1.mp4'));
sf = readFrame(vr);
[H, W, ~] = size(sf);
r1 = round(H * 0.31); r2 = round(H * 0.45);
c1 = round(W * 0.26); c2 = round(W * 0.74);
fprintf('  Frame: %dx%d, Eye ROI: rows %d-%d, cols %d-%d\n', W, H, r1, r2, c1, c2);

% Calibrate
vr.CurrentTime = 0;
be = 0;
for i = 1:5
    f = readFrame(vr);
    g = single(rgb2gray(f));
    p = g(r1:r2, c1:c2);
    [gx, gy] = gradient(p);
    be = be + mean(sqrt(gx(:).^2 + gy(:).^2));
end
be = be / 5;
thr = be * 0.90;
fprintf('  Baseline edges: %.3f\n', be);
fprintf('  Trigger threshold (90%%): %.3f  (10%% drop fires alarm)\n', thr);

% Run detection
vr.CurrentTime = 0;
sc = 0;
fired = 0;
nFrames = min(74, floor(vr.Duration * vr.FrameRate));
for i = 1:nFrames
    if ~hasFrame(vr), break; end
    f = readFrame(vr);
    g = single(rgb2gray(f));
    p = g(r1:r2, c1:c2);
    [gx, gy] = gradient(p);
    ce = mean(sqrt(gx(:).^2 + gy(:).^2));
    cl = (ce < thr);
    if cl
        sc = min(12, sc + 2);
    else
        sc = max(0, sc - 1);
    end
    if sc >= 6 && fired == 0
        fired = i;
    end
    dropPct = ((be - ce) / be) * 100;
    tag = '';
    if fired == i, tag = ' <<< ALARM TRIGGERED >>>'; end
    if mod(i, 10) == 0 || fired == i
        fprintf('  Frame %02d: edges=%.3f drop=%+.1f%% score=%d%s\n', i, ce, dropPct, sc, tag);
    end
end
if fired > 0
    fprintf('  >>> EYE CLOSURE ALARM FIRED at frame %d (%.1fs into video)\n\n', fired, fired / vr.FrameRate);
else
    fprintf('  >>> WARNING: Eye closure alarm NEVER fired in %d frames!\n\n', nFrames);
end

%% 2. HEAD LOWERING TEST
fprintf('=== TEST 2: HEAD LOWERING (dbase/head/h1.mp4) ===\n');
vr2 = VideoReader(fullfile(pwd, 'dbase', 'head', 'h1.mp4'));

% Calibrate skin baseline
vr2.CurrentTime = 0;
bs = 0; by_acc = 0;
for i = 1:5
    f = readFrame(vr2);
    I = single(f(1:2:end, 1:2:end, :));
    cb = 0.148*I(:,:,1) - 0.291*I(:,:,2) + 0.439*I(:,:,3) + 128;
    cr = 0.439*I(:,:,1) - 0.368*I(:,:,2) - 0.071*I(:,:,3) + 128;
    m = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
    bs = bs + sum(m(:));
    [r, ~] = find(m);
    if ~isempty(r), by_acc = by_acc + mean(r); end
end
bs = bs / 5;
by = by_acc / 5;
ys = max(10, round(by));

% Calibrate upper face
vr2.CurrentTime = 0;
bu = 0;
for i = 1:5
    f = readFrame(vr2);
    I = single(f(1:2:end, 1:2:end, :));
    cb = 0.148*I(:,:,1) - 0.291*I(:,:,2) + 0.439*I(:,:,3) + 128;
    cr = 0.439*I(:,:,1) - 0.368*I(:,:,2) - 0.071*I(:,:,3) + 128;
    m = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
    bu = bu + sum(sum(m(1:ys, :)));
end
bu = bu / 5;
fprintf('  Baseline: skin=%d  Y=%.1f px  upper=%d\n', round(bs), by, round(bu));
fprintf('  Head nod triggers on: Y-shift > 5.5 px  OR  upper drop > 12%%\n');

% Run detection
vr2.CurrentTime = 0;
sc2 = 0;
fired2 = 0;
nFrames2 = min(100, floor(vr2.Duration * vr2.FrameRate));
for i = 1:nFrames2
    if ~hasFrame(vr2), break; end
    f = readFrame(vr2);
    I = single(f(1:2:end, 1:2:end, :));
    cb = 0.148*I(:,:,1) - 0.291*I(:,:,2) + 0.439*I(:,:,3) + 128;
    cr = 0.439*I(:,:,1) - 0.368*I(:,:,2) - 0.071*I(:,:,3) + 128;
    m = (cr >= 125 & cr <= 185 & cb >= 75 & cb <= 165);
    cs = sum(m(:));
    [r, ~] = find(m);
    if ~isempty(r), cy = mean(r); else, cy = by + 30; end
    ysh = cy - by;
    us = sum(sum(m(1:ys, :)));
    ud = ((bu - us) / bu) * 100;
    hl = (ysh > 5.5) || (ud > 12) || (cs < bs * 0.85);
    if hl
        sc2 = min(12, sc2 + 2);
    else
        sc2 = max(0, sc2 - 1);
    end
    if sc2 >= 6 && fired2 == 0
        fired2 = i;
    end
    tag = '';
    if fired2 == i, tag = ' <<< ALARM TRIGGERED >>>'; end
    if mod(i, 10) == 0 || fired2 == i
        fprintf('  Frame %02d: yShift=%+.1f px  upperDrop=%+.1f%%  score=%d%s\n', i, ysh, ud, sc2, tag);
    end
end
if fired2 > 0
    fprintf('  >>> HEAD LOWERING ALARM FIRED at frame %d (%.1fs into video)\n\n', fired2, fired2 / vr2.FrameRate);
else
    fprintf('  >>> WARNING: Head lowering alarm NEVER fired in %d frames!\n\n', nFrames2);
end

%% Summary
fprintf('============================================\n');
fprintf(' RESULTS SUMMARY\n');
fprintf('============================================\n');
if fired > 0
    fprintf('  [PASS] Eye Closure Detection:   Alarm at frame %d\n', fired);
else
    fprintf('  [FAIL] Eye Closure Detection:   No alarm triggered\n');
end
if fired2 > 0
    fprintf('  [PASS] Head Lowering Detection: Alarm at frame %d\n', fired2);
else
    fprintf('  [FAIL] Head Lowering Detection: No alarm triggered\n');
end
fprintf('============================================\n');
