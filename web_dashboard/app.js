// ==========================================================================
//  INTELLIGENT DRIVER DROWSINESS DETECTION SYSTEM
//  Real-Time WebRTC Telematics HUD & Presentation Engine
// ==========================================================================

// Global Application State
const state = {
  isStreaming: false,
  isCalibrated: false,
  soundEnabled: true,
  stream: null,
  
  // Baseline Parameters
  baselineEdges: 12.0,
  baselineSkin: 35000,
  
  // Real-Time Metrics
  currEdges: 12.0,
  currSkin: 35000,
  eyeClosedFrames: 0,
  headLoweredFrames: 0,
  fatigueScore: 0,
  isAlarm: false,
  
  // Configuration Limits
  eyeTriggerLimit: 7,   // Consecutive frames for eye closure (~0.7s)
  headTriggerLimit: 10, // Consecutive frames for head drop (~0.5s)
  eyeDropThreshold: 0.65, // 35% drop in edge density
  headDropThreshold: 0.10, // 10% drop in skin area
  
  // Waveform History
  edgeHistory: new Array(60).fill(12.0),
  
  // Simulation Mode
  isSimulating: false,
  simScenario: 'normal',
  simTimer: null
};

// DOM References
const videoEl = document.getElementById('webcamVideo');
const hudCanvas = document.getElementById('hudCanvas');
const hudCtx = hudCanvas.getContext('2d');
const pipCanvas = document.getElementById('pipCanvas');
const pipCtx = pipCanvas.getContext('2d');
const waveCanvas = document.getElementById('waveformCanvas');
const waveCtx = waveCanvas.getContext('2d');

// UI Elements
const btnToggleCam = document.getElementById('btnToggleCam');
const btnRecalibrate = document.getElementById('btnRecalibrate');
const emergencyBanner = document.getElementById('emergencyBanner');
const emergencyTitle = document.getElementById('emergencyTitle');
const emergencySub = document.getElementById('emergencySub');
const calibOverlay = document.getElementById('calibOverlay');
const dangerScoreEl = document.getElementById('dangerScore');
const dangerLabelEl = document.getElementById('dangerLabel');
const gaugeProgressEl = document.getElementById('gaugeProgress');
const topStatusChip = document.getElementById('topStatusChip');
const liveStreamBadge = document.getElementById('liveStreamBadge');
const valEyeEdgesEl = document.getElementById('valEyeEdges');
const valEyeBaseEl = document.getElementById('valEyeBase');
const valEyeRatioEl = document.getElementById('valEyeRatio');
const barEyeRatioEl = document.getElementById('barEyeRatio');
const eyeFrameCountEl = document.getElementById('eyeFrameCount');
const valHeadPixelsEl = document.getElementById('valHeadPixels');
const valHeadBaseEl = document.getElementById('valHeadBase');
const valHeadRatioEl = document.getElementById('valHeadRatio');
const barHeadRatioEl = document.getElementById('barHeadRatio');
const headFrameCountEl = document.getElementById('headFrameCount');
const auditLogEl = document.getElementById('auditLog');

// --------------------------------------------------------------------------
// 1. WEB AUDIO API SYNTHESIZER (880 Hz Triple Burst Alarm)
// --------------------------------------------------------------------------
let audioCtx = null;

function initAudio() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
    }
  }
}

function playAlarmTone(force = false) {
  if (!state.soundEnabled && !force) return;
  initAudio();
  if (!audioCtx) return;
  
  try {
    const now = audioCtx.currentTime;
    const toneFreq = 880; // 880 Hz high alert tone
    const burstDuration = 0.12;
    const gap = 0.08;

    for (let i = 0; i < 3; i++) {
      const startTime = now + i * (burstDuration + gap);
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();

      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(toneFreq, startTime);

      // Attack and decay envelope
      gain.gain.setValueAtTime(0.001, startTime);
      gain.gain.exponentialRampToValueAtTime(0.3, startTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, startTime + burstDuration);

      osc.connect(gain);
      gain.connect(audioCtx.destination);

      osc.start(startTime);
      osc.stop(startTime + burstDuration);
    }
  } catch (err) {
    console.warn('Audio synthesis notice:', err);
  }
}

function toggleAudioAlarm() {
  state.soundEnabled = !state.soundEnabled;
  const btn = document.getElementById('btnAudioToggle');
  const icon = document.getElementById('audioIcon');
  if (state.soundEnabled) {
    icon.textContent = '🔊';
    btn.innerHTML = `<span class="btn-icon">🔊</span> ALARM SOUND: ON`;
    btn.style.color = 'var(--text-main)';
  } else {
    icon.textContent = '🔇';
    btn.innerHTML = `<span class="btn-icon">🔇</span> ALARM SOUND: MUTED`;
    btn.style.color = 'var(--color-amber)';
  }
}

// --------------------------------------------------------------------------
// 2. WEBCAM STREAM CONTROLS & LIFECYCLE
// --------------------------------------------------------------------------
async function toggleCamera() {
  if (state.isStreaming) {
    stopCamera();
  } else {
    await startCamera();
  }
}

async function startCamera() {
  try {
    initAudio();
    const constraints = {
      video: {
        width: { ideal: 640 },
        height: { ideal: 480 },
        facingMode: 'user'
      },
      audio: false
    };
    
    state.stream = await navigator.mediaDevices.getUserMedia(constraints);
    videoEl.srcObject = state.stream;
    await videoEl.play();

    state.isStreaming = true;
    state.isSimulating = false;
    btnToggleCam.innerHTML = `<span class="btn-icon">⏹</span> STOP CAMERA`;
    btnToggleCam.classList.remove('btn-primary');
    btnToggleCam.classList.add('btn-secondary');
    btnRecalibrate.disabled = false;
    liveStreamBadge.textContent = 'LIVE 30 FPS';
    liveStreamBadge.style.color = 'var(--color-emerald)';

    logAudit('Camera stream connected: 640×480 @ 30 FPS');
    
    // Start calibration
    calibrateBaseline();

    // Start Real-Time CV Processing Loop
    requestAnimationFrame(processVideoFrame);
  } catch (err) {
    console.error('Camera access error:', err);
    alert('Unable to access webcam: ' + err.message + '\n\nYou can still use the "PRESENTATION SIMULATOR PRESETS" below to test the full system without a camera!');
    startSimulationMode();
  }
}

function stopCamera() {
  if (state.stream) {
    state.stream.getTracks().forEach(track => track.stop());
    state.stream = null;
  }
  state.isStreaming = false;
  btnToggleCam.innerHTML = `<span class="btn-icon">▶</span> START CAMERA`;
  btnToggleCam.classList.remove('btn-secondary');
  btnToggleCam.classList.add('btn-primary');
  btnRecalibrate.disabled = true;
  liveStreamBadge.textContent = 'STANDBY';
  liveStreamBadge.style.color = 'var(--text-muted)';
  
  // Render standby frame on canvas
  drawStandbyFrame();
  logAudit('Camera stream stopped cleanly.');
}

// --------------------------------------------------------------------------
// 3. BASELINE CALIBRATION
// --------------------------------------------------------------------------
function calibrateBaseline() {
  calibOverlay.classList.add('active');
  logAudit('Initiated 5-frame baseline driver calibration...');

  let calibFrames = 0;
  let edgeAccum = 0;
  let skinAccum = 0;

  const calibInterval = setInterval(() => {
    if (!state.isStreaming && !state.isSimulating) {
      clearInterval(calibInterval);
      calibOverlay.classList.remove('active');
      return;
    }

    const metrics = computeFrameMetrics();
    edgeAccum += metrics.edges;
    skinAccum += metrics.skin;
    calibFrames++;

    if (calibFrames >= 5) {
      clearInterval(calibInterval);
      state.baselineEdges = Math.max(1.0, edgeAccum / 5);
      state.baselineSkin = Math.max(100, skinAccum / 5);
      state.isCalibrated = true;
      calibOverlay.classList.remove('active');

      valEyeBaseEl.textContent = state.baselineEdges.toFixed(1);
      valHeadBaseEl.textContent = Math.round(state.baselineSkin).toLocaleString();

      logAudit(`✓ Calibration complete. Base Edges: ${state.baselineEdges.toFixed(1)}, Base Skin: ${Math.round(state.baselineSkin)}`);
    }
  }, 200);
}

// --------------------------------------------------------------------------
// 4. REAL-TIME COMPUTER VISION FRAME PROCESSOR
// --------------------------------------------------------------------------
// Off-screen canvas for pixel reading
const offCanvas = document.createElement('canvas');
offCanvas.width = 640;
offCanvas.height = 480;
const offCtx = offCanvas.getContext('2d');

function computeFrameMetrics() {
  if (!state.isStreaming && !state.isSimulating) {
    return { edges: 12.0, skin: 35000, skinMaskData: null };
  }

  // Draw current video frame to off-screen buffer
  if (state.isStreaming) {
    offCtx.drawImage(videoEl, 0, 0, 640, 480);
  }

  const frameData = offCtx.getImageData(0, 0, 640, 480);
  const data = frameData.data;

  // 1. Process Eye Region (Rows: 28% - 56%, Cols: 15% - 85%)
  const r1 = Math.round(480 * 0.28);
  const r2 = Math.round(480 * 0.56);
  const c1 = Math.round(640 * 0.15);
  const c2 = Math.round(640 * 0.85);

  let edgeSum = 0;
  let pixelSamples = 0;

  // Step 2 for high frame rate performance
  for (let y = r1; y < r2 - 1; y += 2) {
    for (let x = c1; x < c2 - 1; x += 2) {
      const idx = (y * 640 + x) * 4;
      const idxRight = (y * 640 + (x + 1)) * 4;
      const idxDown = ((y + 1) * 640 + x) * 4;

      // Luminance: 0.299R + 0.587G + 0.114B
      const luma = 0.299 * data[idx] + 0.587 * data[idx + 1] + 0.114 * data[idx + 2];
      const lumaRight = 0.299 * data[idxRight] + 0.587 * data[idxRight + 1] + 0.114 * data[idxRight + 2];
      const lumaDown = 0.299 * data[idxDown] + 0.587 * data[idxDown + 1] + 0.114 * data[idxDown + 2];

      const gx = lumaRight - luma;
      const gy = lumaDown - luma;
      edgeSum += Math.sqrt(gx * gx + gy * gy);
      pixelSamples++;
    }
  }
  const avgEdges = pixelSamples > 0 ? (edgeSum / pixelSamples) : 10.0;

  // 2. Process Head Lowering YCbCr Skin Segmentation
  let skinCount = 0;
  const pipData = pipCtx.createImageData(160, 120);
  const pipPixels = pipData.data;

  // Downsample to 160x120 for PIP rendering
  for (let py = 0; py < 120; py++) {
    for (let px = 0; px < 160; px++) {
      const srcX = px * 4;
      const srcY = py * 4;
      const sIdx = (srcY * 640 + srcX) * 4;

      const r = data[sIdx];
      const g = data[sIdx + 1];
      const b = data[sIdx + 2];

      // YCbCr equations from project specification
      const cb = 0.148 * r - 0.291 * g + 0.439 * b + 128;
      const cr = 0.439 * r - 0.368 * g - 0.071 * b + 128;

      const pIdx = (py * 160 + px) * 4;
      if (cr > 130 && cr < 180 && cb > 80 && cb < 160) {
        skinCount += 16; // scaled to 640x480 equivalent
        // Cyan mask in PIP
        pipPixels[pIdx] = 0;
        pipPixels[pIdx + 1] = 230;
        pipPixels[pIdx + 2] = 255;
        pipPixels[pIdx + 3] = 255;
      } else {
        pipPixels[pIdx] = 10;
        pipPixels[pIdx + 1] = 14;
        pipPixels[pIdx + 2] = 24;
        pipPixels[pIdx + 3] = 255;
      }
    }
  }

  return { edges: avgEdges, skin: skinCount, pipImageData: pipData };
}

function processVideoFrame() {
  if (!state.isStreaming && !state.isSimulating) return;

  const metrics = computeFrameMetrics();
  state.currEdges = metrics.edges;
  state.currSkin = metrics.skin;

  // Update Waveform History
  state.edgeHistory.push(metrics.edges);
  if (state.edgeHistory.length > 60) state.edgeHistory.shift();

  // Draw Camera Feed onto Canvas
  if (state.isStreaming) {
    hudCtx.drawImage(videoEl, 0, 0, 640, 480);
  } else if (state.isSimulating) {
    hudCtx.drawImage(offCanvas, 0, 0, 640, 480);
  }

  // Draw PIP Skin Mask
  if (metrics.pipImageData) {
    pipCtx.putImageData(metrics.pipImageData, 0, 0);
  }

  // Evaluate Drowsiness Criteria
  evaluateDrowsiness();

  // Draw Cockpit HUD Reticles & Overlays
  drawCockpitHUD();

  // Draw Real-Time Waveform
  drawWaveform();

  // Update Telemetry Panel Numbers
  updateTelemetryUI();

  // Loop
  requestAnimationFrame(processVideoFrame);
}

// --------------------------------------------------------------------------
// 5. DROWSINESS EVALUATION & ALARM LOGIC
// --------------------------------------------------------------------------
let lastAlarmSoundTime = 0;

function evaluateDrowsiness() {
  const edgeThreshold = state.baselineEdges * state.eyeDropThreshold;
  const isEyesClosed = state.currEdges < edgeThreshold;

  const skinDropThreshold = state.baselineSkin * state.headDropThreshold;
  const isHeadLowered = (state.baselineSkin - state.currSkin) > skinDropThreshold;

  // Eye Counter
  if (isEyesClosed) {
    state.eyeClosedFrames++;
  } else {
    state.eyeClosedFrames = 0; // Instant reset
  }

  // Head Lowering Counter
  if (isHeadLowered) {
    state.headLoweredFrames++;
  } else {
    state.headLoweredFrames = 0; // Instant reset
  }

  // Dangerous condition
  const eyeTriggered = state.eyeClosedFrames >= state.eyeTriggerLimit;
  const headTriggered = state.headLoweredFrames >= state.headTriggerLimit;
  const wasAlarm = state.isAlarm;

  state.isAlarm = eyeTriggered || headTriggered;

  // Danger Score (0 - 100%)
  const eyeDanger = Math.min(100, (state.eyeClosedFrames / state.eyeTriggerLimit) * 100);
  const headDanger = Math.min(100, (state.headLoweredFrames / state.headTriggerLimit) * 100);
  state.fatigueScore = Math.round(Math.max(eyeDanger, headDanger) * 0.75 + (eyeDanger * headDanger / 100) * 0.25);

  // Trigger Sound & Alerts
  if (state.isAlarm) {
    const now = Date.now();
    if (now - lastAlarmSoundTime > 900) {
      playAlarmTone();
      lastAlarmSoundTime = now;
    }

    if (!wasAlarm) {
      const cause = eyeTriggered ? 'PROLONGED EYE CLOSURE' : 'HEAD LOWERED';
      logAudit(`🚨 [CRITICAL ALARM] Drowsiness event triggered: ${cause}!`, true);
    }
  }
}

// --------------------------------------------------------------------------
// 6. HUD OVERLAY RENDERING (Canvas 2D)
// --------------------------------------------------------------------------
function drawCockpitHUD() {
  const w = hudCanvas.width;
  const h = hudCanvas.height;

  // 1. Target Reticle Coordinates (Eyes ROI)
  const r1 = Math.round(h * 0.28);
  const r2 = Math.round(h * 0.56);
  const c1 = Math.round(w * 0.15);
  const c2 = Math.round(w * 0.85);

  let reticleColor = '#00e676';
  if (state.eyeClosedFrames > 2 && !state.isAlarm) {
    reticleColor = '#ffb300';
  } else if (state.isAlarm) {
    reticleColor = '#ff1744';
  }

  hudCtx.save();
  hudCtx.lineWidth = 3;
  hudCtx.strokeStyle = reticleColor;
  hudCtx.shadowColor = reticleColor;
  hudCtx.shadowBlur = 10;

  // Corner brackets
  const corner = 24;
  // Top-Left
  hudCtx.beginPath();
  hudCtx.moveTo(c1, r1 + corner);
  hudCtx.lineTo(c1, r1);
  hudCtx.lineTo(c1 + corner, r1);
  hudCtx.stroke();

  // Top-Right
  hudCtx.beginPath();
  hudCtx.moveTo(c2 - corner, r1);
  hudCtx.lineTo(c2, r1);
  hudCtx.lineTo(c2, r1 + corner);
  hudCtx.stroke();

  // Bottom-Left
  hudCtx.beginPath();
  hudCtx.moveTo(c1, r2 - corner);
  hudCtx.lineTo(c1, r2);
  hudCtx.lineTo(c1 + corner, r2);
  hudCtx.stroke();

  // Bottom-Right
  hudCtx.beginPath();
  hudCtx.moveTo(c2 - corner, r2);
  hudCtx.lineTo(c2, r2);
  hudCtx.lineTo(c2, r2 - corner);
  hudCtx.stroke();

  // Label above eye reticle
  hudCtx.font = '600 12px Rajdhani';
  hudCtx.fillStyle = reticleColor;
  hudCtx.fillText(`EYE OPTICAL TRACKER [${Math.round((state.currEdges / Math.max(1, state.baselineEdges)) * 100)}%]`, c1 + 4, r1 - 8);

  // Crosshairs in Center
  hudCtx.lineWidth = 1;
  hudCtx.strokeStyle = 'rgba(0, 229, 255, 0.4)';
  const cx = (c1 + c2) / 2;
  const cy = (r1 + r2) / 2;
  hudCtx.beginPath();
  hudCtx.moveTo(cx - 15, cy); hudCtx.lineTo(cx + 15, cy);
  hudCtx.moveTo(cx, cy - 15); hudCtx.lineTo(cx, cy + 15);
  hudCtx.stroke();

  // Top Status Bar Overlay
  hudCtx.fillStyle = 'rgba(8, 12, 20, 0.75)';
  hudCtx.fillRect(0, 0, w, 32);

  hudCtx.font = '700 11px Orbitron';
  if (state.isAlarm) {
    hudCtx.fillStyle = '#ff1744';
    hudCtx.fillText('🚨 CRITICAL ALERT: DRIVER DROWSINESS DETECTED', 16, 21);
  } else if (state.fatigueScore > 35) {
    hudCtx.fillStyle = '#ffb300';
    hudCtx.fillText('⚠️ CAUTION: FATIGUE ELEVATION OBSERVED', 16, 21);
  } else {
    hudCtx.fillStyle = '#00e676';
    hudCtx.fillText('● SYSTEM ACTIVE: DRIVER FULLY ALERT', 16, 21);
  }

  // Timestamp on HUD
  hudCtx.font = '600 11px Rajdhani';
  hudCtx.fillStyle = '#8b99b5';
  hudCtx.fillText(`EDGES: ${state.currEdges.toFixed(1)} | SKIN: ${Math.round(state.currSkin)}`, w - 240, 21);

  hudCtx.restore();
}

// --------------------------------------------------------------------------
// 7. REAL-TIME WAVEFORM OSCILLOGRAM
// --------------------------------------------------------------------------
function drawWaveform() {
  const w = waveCanvas.width;
  const h = waveCanvas.height;
  waveCtx.clearRect(0, 0, w, h);

  // Background Grid Lines
  waveCtx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
  waveCtx.lineWidth = 1;
  waveCtx.beginPath();
  waveCtx.moveTo(0, h * 0.35); waveCtx.lineTo(w, h * 0.35);
  waveCtx.moveTo(0, h * 0.70); waveCtx.lineTo(w, h * 0.70);
  waveCtx.stroke();

  // Threshold Line
  const threshY = h - (state.baselineEdges * state.eyeDropThreshold / 30) * h;
  waveCtx.strokeStyle = 'rgba(255, 23, 68, 0.4)';
  waveCtx.setLineDash([4, 4]);
  waveCtx.beginPath();
  waveCtx.moveTo(0, threshY);
  waveCtx.lineTo(w, threshY);
  waveCtx.stroke();
  waveCtx.setLineDash([]);

  // Plot Data
  const pts = state.edgeHistory;
  if (pts.length < 2) return;

  waveCtx.beginPath();
  waveCtx.strokeStyle = state.isAlarm ? '#ff1744' : '#00e5ff';
  waveCtx.lineWidth = 2;

  for (let i = 0; i < pts.length; i++) {
    const x = (i / (pts.length - 1)) * w;
    const y = Math.max(4, Math.min(h - 4, h - (pts[i] / 30) * h));
    if (i === 0) waveCtx.moveTo(x, y);
    else waveCtx.lineTo(x, y);
  }
  waveCtx.stroke();
}

// --------------------------------------------------------------------------
// 8. TELEMETRY UI BINDINGS
// --------------------------------------------------------------------------
function updateTelemetryUI() {
  // Danger Gauge
  const maxOffset = 251.3;
  const offset = maxOffset - (state.fatigueScore / 100) * maxOffset;
  gaugeProgressEl.style.strokeDashoffset = offset;
  dangerScoreEl.textContent = `${state.fatigueScore}%`;

  if (state.isAlarm) {
    gaugeProgressEl.style.stroke = 'var(--color-crimson)';
    dangerScoreEl.style.color = 'var(--color-crimson)';
    dangerLabelEl.textContent = 'CRITICAL DROWSY';
    topStatusChip.textContent = 'DROWSY ALARM';
    topStatusChip.className = 'status-chip danger';
    emergencyBanner.classList.add('active');
    emergencyTitle.textContent = state.eyeClosedFrames >= state.eyeTriggerLimit ? 'PROLONGED EYE CLOSURE!' : 'HEAD LOWERED / DROOP!';
  } else if (state.fatigueScore > 35) {
    gaugeProgressEl.style.stroke = 'var(--color-amber)';
    dangerScoreEl.style.color = 'var(--color-amber)';
    dangerLabelEl.textContent = 'FATIGUE CAUTION';
    topStatusChip.textContent = 'ELEVATED FATIGUE';
    topStatusChip.className = 'status-chip warning';
    emergencyBanner.classList.remove('active');
  } else {
    gaugeProgressEl.style.stroke = 'var(--color-emerald)';
    dangerScoreEl.style.color = 'var(--color-emerald)';
    dangerLabelEl.textContent = 'DRIVER ALERT';
    topStatusChip.textContent = 'NORMAL (SAFE)';
    topStatusChip.className = 'status-chip safe';
    emergencyBanner.classList.remove('active');
  }

  // Module 1 UI
  valEyeEdgesEl.textContent = state.currEdges.toFixed(1);
  const eyeRatio = Math.round((state.currEdges / Math.max(1, state.baselineEdges)) * 100);
  valEyeRatioEl.textContent = `${eyeRatio}%`;
  barEyeRatioEl.style.width = `${Math.min(100, eyeRatio)}%`;
  barEyeRatioEl.className = `progress-bar ${eyeRatio < 65 ? 'danger' : (eyeRatio < 85 ? 'warning' : 'safe')}`;
  eyeFrameCountEl.textContent = `${state.eyeClosedFrames} / ${state.eyeTriggerLimit}`;

  // Update Eye Dot Indicators
  const eyeDots = document.querySelectorAll('#eyeFrameDots .dot');
  eyeDots.forEach((dot, idx) => {
    if (idx < state.eyeClosedFrames) dot.classList.add('active');
    else dot.classList.remove('active');
  });

  // Module 2 UI
  valHeadPixelsEl.textContent = Math.round(state.currSkin).toLocaleString();
  const headRatio = Math.round((state.currSkin / Math.max(1, state.baselineSkin)) * 100);
  valHeadRatioEl.textContent = `${headRatio}%`;
  barHeadRatioEl.style.width = `${Math.min(100, headRatio)}%`;
  barHeadRatioEl.className = `progress-bar ${headRatio < 90 ? 'danger' : (headRatio < 95 ? 'warning' : 'safe')}`;
  headFrameCountEl.textContent = `${state.headLoweredFrames} / ${state.headTriggerLimit}`;

  // Update Head Dot Indicators
  const headDots = document.querySelectorAll('#headFrameDots .dot');
  headDots.forEach((dot, idx) => {
    if (idx < state.headLoweredFrames) dot.classList.add('active');
    else dot.classList.remove('active');
  });
}

// --------------------------------------------------------------------------
// 9. PRESENTATION SIMULATOR PRESETS (FOR DEMOS WITHOUT CAMERA)
// --------------------------------------------------------------------------
function simulateScenario(scenario) {
  initAudio();
  if (state.isStreaming) {
    stopCamera();
  }

  state.isSimulating = true;
  state.isCalibrated = true;
  state.simScenario = scenario;
  btnToggleCam.innerHTML = `<span class="btn-icon">⏹</span> STOP SIMULATOR`;
  liveStreamBadge.textContent = `SIM: ${scenario.toUpperCase()}`;
  liveStreamBadge.style.color = 'var(--color-amber)';

  if (state.simTimer) clearInterval(state.simTimer);

  logAudit(`Simulator mode started: scenario [${scenario}]`);

  // Animate simulation frames
  let tick = 0;
  state.simTimer = setInterval(() => {
    tick++;
    drawSimulatedDriverFrame(scenario, tick);
    processVideoFrame();
  }, 100);
}

function startSimulationMode() {
  simulateScenario('normal');
}

function drawSimulatedDriverFrame(scenario, tick) {
  const w = 640; const h = 480;
  offCtx.fillStyle = '#0f172a';
  offCtx.fillRect(0, 0, w, h);

  // Draw Driver Silhouette
  offCtx.fillStyle = '#1e293b';
  // Shoulders
  offCtx.beginPath();
  offCtx.ellipse(320, 480, 220, 150, 0, 0, Math.PI * 2);
  offCtx.fill();

  let headOffsetY = 0;
  if (scenario === 'headdrop' || scenario === 'critical') {
    headOffsetY = 70; // head tilts down
  }

  // Head Oval
  offCtx.fillStyle = '#f8d7b8'; // skin tone
  offCtx.beginPath();
  offCtx.ellipse(320, 230 + headOffsetY, 85, 115, 0, 0, Math.PI * 2);
  offCtx.fill();

  // Eyes
  const eyesShut = (scenario === 'microsleep' || scenario === 'critical');
  if (eyesShut) {
    // Closed eyelids: curved slit with zero internal edges
    offCtx.strokeStyle = '#334155';
    offCtx.lineWidth = 3;
    offCtx.beginPath();
    offCtx.arc(285, 215 + headOffsetY, 16, 0.2, Math.PI - 0.2);
    offCtx.stroke();
    offCtx.beginPath();
    offCtx.arc(355, 215 + headOffsetY, 16, 0.2, Math.PI - 0.2);
    offCtx.stroke();
  } else {
    // Open eyes: sclera + dark iris (produces strong edge gradients!)
    offCtx.fillStyle = '#ffffff';
    offCtx.beginPath();
    offCtx.ellipse(285, 215 + headOffsetY, 18, 12, 0, 0, Math.PI * 2);
    offCtx.ellipse(355, 215 + headOffsetY, 18, 12, 0, 0, Math.PI * 2);
    offCtx.fill();

    offCtx.fillStyle = '#0f172a';
    offCtx.beginPath();
    offCtx.arc(285, 215 + headOffsetY, 7, 0, Math.PI * 2);
    offCtx.arc(355, 215 + headOffsetY, 7, 0, Math.PI * 2);
    offCtx.fill();
  }

  // Mouth
  offCtx.strokeStyle = '#c2410c';
  offCtx.lineWidth = 3;
  offCtx.beginPath();
  offCtx.arc(320, 280 + headOffsetY, 22, 0.2, Math.PI - 0.2);
  offCtx.stroke();
}

function drawStandbyFrame() {
  hudCtx.fillStyle = '#090d16';
  hudCtx.fillRect(0, 0, 640, 480);

  hudCtx.fillStyle = 'rgba(0, 229, 255, 0.2)';
  hudCtx.font = '700 16px Orbitron';
  hudCtx.textAlign = 'center';
  hudCtx.fillText('CAMERA STANDBY', 320, 220);

  hudCtx.font = '500 13px Rajdhani';
  hudCtx.fillStyle = '#8b99b5';
  hudCtx.fillText('Click [START CAMERA] or test with [PRESENTATION SIMULATOR PRESETS]', 320, 250);
  hudCtx.textAlign = 'left';
}

// --------------------------------------------------------------------------
// 10. DIAGNOSTIC SNAPSHOT DOWNLOADER
// --------------------------------------------------------------------------
function captureSnapshot() {
  const link = document.createElement('a');
  const now = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  link.download = `driver_safety_snapshot_${now}.png`;
  link.href = hudCanvas.toDataURL('image/png');
  link.click();
  logAudit(`📸 Snapshot saved: ${link.download}`);
}

// --------------------------------------------------------------------------
// 11. AUDIT LOGGING
// --------------------------------------------------------------------------
function logAudit(message, isAlarm = false) {
  const time = new Date().toLocaleTimeString();
  const entry = document.createElement('div');
  entry.className = `log-entry ${isAlarm ? 'alarm' : ''}`;
  entry.innerHTML = `<span class="log-time">[${time}]</span> ${message}`;
  auditLogEl.insertBefore(entry, auditLogEl.firstChild);
  if (auditLogEl.children.length > 20) {
    auditLogEl.removeChild(auditLogEl.lastChild);
  }
}

// --------------------------------------------------------------------------
// 12. TAB SWITCHING & PRESENTATION SLIDE CONTROLLER
// --------------------------------------------------------------------------
function switchTab(tabId) {
  document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

  if (tabId === 'live') {
    document.getElementById('tabLiveBtn').classList.add('active');
    document.getElementById('tabLive').classList.add('active');
  } else if (tabId === 'presentation') {
    document.getElementById('tabPresentationBtn').classList.add('active');
    document.getElementById('tabPresentation').classList.add('active');
  } else if (tabId === 'architecture') {
    document.getElementById('tabArchitectureBtn').classList.add('active');
    document.getElementById('tabArchitecture').classList.add('active');
  }
}

let currentSlide = 0;
const slides = document.querySelectorAll('.slides-container .slide');
const slideCounterEl = document.getElementById('slideCounter');

function updateSlideView() {
  slides.forEach((s, idx) => {
    s.classList.toggle('active', idx === currentSlide);
  });
  if (slideCounterEl) {
    slideCounterEl.textContent = `Slide ${currentSlide + 1} of ${slides.length}`;
  }
}

function nextSlide() {
  currentSlide = (currentSlide + 1) % slides.length;
  updateSlideView();
}

function prevSlide() {
  currentSlide = (currentSlide - 1 + slides.length) % slides.length;
  updateSlideView();
}

// Keyboard shortcuts for slides
window.addEventListener('keydown', (e) => {
  if (document.getElementById('tabPresentation').classList.contains('active')) {
    if (e.key === 'ArrowRight' || e.key === 'PageDown') nextSlide();
    if (e.key === 'ArrowLeft' || e.key === 'PageUp') prevSlide();
  }
});

// Update Clock
setInterval(() => {
  const clockEl = document.getElementById('hudClock');
  if (clockEl) clockEl.textContent = new Date().toLocaleTimeString();
}, 1000);

// Initialize initial standby frame
drawStandbyFrame();
updateSlideView();
logAudit('System initialization completed. Ready for demo.');
