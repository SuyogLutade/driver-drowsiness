clear all;
clc


%%%%%%-------video input------%%%%%%
cam = webcam; % Connects to default webcam
pause(2); % IMPORTANT: Give the webcam 2 seconds to turn on and adjust lighting!
I = snapshot(cam);
rate = 30; % Assumed frame rate



%%%%%-----working on 1st frame------%%%%%%%%%
figure, imshow(I)
I = imresize( I, [360 640]);
I = double(I);
[hue,s,v] = rgb2hsv(I);
cb = 0.148* I(:,:,1) - 0.291* I(:,:,2) + 0.439 * I(:,:,3) + 128;
cr = 0.439 * I(:,:,1) - 0.368 * I(:,:,2) -0.071 * I(:,:,3) + 128;
[w h] = size(I(:,:,1));

count = 0;
for i=1:w
    for j=1:h
        if cr(i,j)>130 && cr(i,j)<180 && cb(i,j)>80 && cb(i,j)<160
            segment(i,j)=1;
            count = count + 1;
        else
            segment(i,j)=0;
        end
    end
end

im(:,:,1)=I(:,:,1).*segment;
im(:,:,2)=I(:,:,2).*segment;
im(:,:,3)=I(:,:,3).*segment;
f = figure; imshow(uint8(im));


%--------Calculating the percentage--------------------
count
pixel_count = (count*10)/100; % Require a 10% drop in skin pixels to count as head lowering





%------------Working on rest frames
num = 0;
t = 2;

while ishandle(f) % Loop until figure is closed
    count1 = 0;
    I = snapshot(cam);
    I = imresize( I, [360 640]);
    I = double(I);
    [hue,s,v] = rgb2hsv(I);
    cb = 0.148* I(:,:,1) - 0.291* I(:,:,2) + 0.439 * I(:,:,3) + 128;
    cr = 0.439 * I(:,:,1) - 0.368 * I(:,:,2) -0.071 * I(:,:,3) + 128;
    [w h] = size(I(:,:,1));

    for i=1:w
        for j=1:h
            if cr(i,j)>130 && cr(i,j)<180 && cb(i,j)>80 && cb(i,j)<160
                segment1(i,j)=1;
                count1 = count1 + 1;
            else
                segment1(i,j)=0;
            end
        end
    end 
    
    
    im(:,:,1)=I(:,:,1).*segment1;
    im(:,:,2)=I(:,:,2).*segment1;
    im(:,:,3)=I(:,:,3).*segment1;
    try figure(f); imshow(uint8(im)); catch, break; end
    
    disp(['Skin pixels detected: ', num2str(count1), ' (Baseline: ', num2str(count), ')']);
    
    if count - count1 > pixel_count
        num = num + 1; % Head is lowered, accumulate
    else
        num = 0; % Head is up, RESET counter immediately
    end;
    
    if num > 10 % Require 10 CONSECUTIVE low-skin frames before alarm
        disp('HEAD LOWERING DETECTED - WAKE UP!');
        % Generate loud alarm tone
        fs = 8000;
        t_alarm = 0:1/fs:0.4;
        alarm = sin(2*pi*880*t_alarm); % 880 Hz tone
        sound([alarm alarm alarm], fs);
        num = 0;
    end
    t = t + 2;
    pause(0.05); % Small pause for figure updates
end
clear cam;




