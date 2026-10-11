# ⚡ Quickstart Guide — Intelligent Driver Drowsiness Detection

Get the system up and running in under 60 seconds.

---

## 🎯 1. Running in MATLAB (Recommended for Technical Evaluation)

### Step 1: Open MATLAB
Open MATLAB and navigate to this folder:
```matlab
cd('c:\Users\HP\OneDrive\Desktop\Driver Drowsiness\Drowsiness-Detection - Copy')
```

### Step 2: Launch the Master Menu
In the Command Window, run:
```matlab
run_system
```
You will be greeted with the master launcher:
```text
Available Operational Modules:
  [1] 🖥️  Launch Interactive GUI Dashboard (Recommended)
  [2] 👁️  Run Module 1: Eye Closure Detection (Edge-Density)
  [3] 🤦  Run Module 2: Head Lowering Detection (YCbCr Skin Segmentation)
  [4] 🌐  Open Web Presentation & Live Browser Dashboard
  [5] 🔧  Run Camera Hardware Diagnostic Check
  [0] ❌  Exit
```

### Direct Commands:
- To launch the **Interactive GUI Dashboard** immediately:
  ```matlab
  DriverSafetyGUI
  ```
- To run **Module 1 (Eye Closure Detection)** standalone:
  ```matlab
  new
  ```
- To run **Module 2 (Head Dropping Detection)** standalone:
  ```matlab
  HeadLowering
  ```

---

## 🌐 2. Running in Web Browser (No MATLAB Required)

If you are presenting on a laptop, tablet, or projector without MATLAB:
1. Double-click [`index.html`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/index.html) in this directory.
2. It will open the **Automopilot Safety HUD** in your default web browser (Chrome, Edge, Firefox).
3. Click **▶ START CAMERA** to test live webcam drowsiness detection in your browser.
4. Or click any of the **PRESENTATION SIMULATOR PRESETS** (`✓ Normal Driving`, `👁️ Eye Closure`, `🤦 Head Dropping`, `🚨 Dual Critical Alarm`) to demonstrate fatigue scenarios on the spot!
5. Click **PROJECT VIVA DECK** in the header to view and present the 8-slide presentation deck.

---

## 📋 3. Hardware Requirements & Verification
- **Webcam:** Any built-in laptop webcam or USB webcam (DroidCam also supported).
- **Audio:** Speakers or headphones enabled for the 880 Hz audible alert.
- **Diagnostics:** Run option `[5]` in `run_system` or run:
  ```matlab
  webcamlist
  ```
  to verify camera detection.

---

## 📚 4. Project Files Reference

| File | Purpose |
|:---|:---|
| [`run_system.m`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/run_system.m) | Master interactive menu launcher |
| [`DriverSafetyGUI.m`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/DriverSafetyGUI.m) | High-definition MATLAB telematics GUI with real-time HUD |
| [`new.m`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/new.m) | Module 1: Eye closure gradient edge-density detection |
| [`HeadLowering.m`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/HeadLowering.m) | Module 2: Head dropping vectorized YCbCr skin detection (60+ FPS) |
| [`index.html`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/index.html) | Root shortcut launcher to browser dashboard |
| [`web_dashboard/`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/web_dashboard/) | Standalone browser HUD with WebRTC & Viva slide deck |
| [`PRESENTATION_GUIDE.md`](file:///c:/Users/HP/OneDrive/Desktop/Driver%20Drowsiness/Drowsiness-Detection%20-%20Copy/PRESENTATION_GUIDE.md) | Viva defense script, elevator pitch & Top 10 Q&A answers |
| `dbase/` & `resources/` | Untouched original project dataset and project assets |
