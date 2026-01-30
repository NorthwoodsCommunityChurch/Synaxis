# Testing Guide for Synaxis

## Overview

This document covers three methods to test the RossTalk and ProPresenter integrations without physical hardware.

---

## Method 1: Python RossTalk Simulator

The simulator acts as a Ross Carbonite/Ultrix switcher that your app connects to.

### Setup

```bash
cd path/to/Synaxis
python3 ross_simulator.py
```

### Configure the App

1. In Settings, set Carbonite Host to: `127.0.0.1`
2. Port: `7788` (default)
3. Enable Carbonite and Connect

### Simulator Menu

Once connected, you can send commands:

| Choice | Command | Description |
|--------|---------|-------------|
| 1 | MECUT | Program cut (triggers CUT event) |
| 2 | MEAUTO | Auto transition |
| 3 | SELECT | Source selection |
| 4 | KEYCUT ON | Turn keyer ON |
| 5 | KEYCUT OFF | Turn keyer OFF |
| 6 | KEYAUTO ON | Auto keyer ON |
| 7 | KEYAUTO OFF | Auto keyer OFF |
| 10 | Full Sequence | Simulates a complete production |
| 11 | Keyer Toggle | Toggles keyer every 3 seconds |

---

## Method 2: Manual Netcat Testing

Use `nc` (netcat) to act as a Ross switcher server.

### Start a Server

```bash
# Start listening on port 7788
nc -l 7788
```

### Connect the App

Configure Synaxis to connect to `127.0.0.1:7788`

### Send Commands

Type these commands in the netcat terminal (press Enter after each):

#### Camera Cuts
```
MECUT ME:1
SELECT PGM:1:IN:1
SELECT PGM:1:IN:2
SELECT PGM:1:IN:3
```

#### Keyer Controls
```
# Keyer 1 ON
KEYCUT ME:1:1

# Keyer 1 OFF
KEYCUT ME:1:1:OFF

# Keyer 2 ON (auto transition)
KEYAUTO ME:1:2

# Keyer 2 OFF
KEYAUTO ME:1:2:OFF
```

#### Auto Transitions
```
MEAUTO ME:1
```

#### Ultrix Router Commands
```
XPT vid 1 3
SALVO 1
```

### Example Test Session

```bash
# Start netcat server
nc -l 7788

# After app connects, type these (one per line):
SELECT PGM:1:IN:1
KEYCUT ME:1:1
KEYCUT ME:1:1:OFF
MECUT ME:1
SELECT PGM:1:IN:2
```

---

## Method 3: Built-in Test Buttons

The Diagnostics view has test buttons to simulate events directly in the app.

### Access

1. Open the app
2. Go to Diagnostics tab

### Available Tests

| Button | Event Type | Description |
|--------|-----------|-------------|
| Test Cut | CUT | Simulates camera cut to IN:3 |
| Test Transition | TRANSITION | Simulates auto transition |
| Key ON | KEY_ON | Turns selected keyer on |
| Key OFF | KEY_OFF | Turns selected keyer off |
| Send Slide Change | GRAPHIC_CHANGE | Simulates ProPresenter slide change |
| Run Full Test | Multiple | Runs complete sequence with delays |

### Keyer Selection

Use the segmented picker (1-8) to choose which keyer to test.

### Full Test Sequence

The "Run Full Test" button simulates:
1. Cut to camera 1
2. Keyer ON (500ms delay)
3. Slide 1 (1s delay)
4. Slide 2 (2s delay)
5. Slide 3 (2s delay)
6. Keyer OFF (1.5s delay)
7. Cut to camera 2

---

## Testing the Complete Workflow

### Test Keyer + ProPresenter Integration

1. **Start Recording** in the app
2. **Send these events** (via any method):
   ```
   KEYCUT ME:1:1        # Keyer 1 ON
   [Slide change 1]     # Via Test button
   [Slide change 2]
   [Slide change 3]
   KEYCUT ME:1:1:OFF    # Keyer 1 OFF
   ```
3. **Stop Recording**
4. **Export to Premiere XML**
5. **Verify**: The XML should only contain slide clips during the time Keyer 1 was ON

### Expected XML Output

When you export, each slide that was displayed while the keyer was ON should appear as a separate clip on the graphics track:

```
|--Keyer ON--|---Slide 1---|---Slide 2---|---Slide 3---|--Keyer OFF--|
             ^-----------------------------------------^
             Only this portion appears in the timeline
```

---

## Troubleshooting

### Simulator won't start
- Check if port 7788 is already in use: `lsof -i :7788`
- Kill any existing process or use a different port

### App won't connect
- Verify IP address and port in Settings
- Check firewall settings
- Ensure the simulator/netcat is running BEFORE connecting

### No events appearing
- Check the Diagnostics view for connection status
- Look at the "Recent Events" section
- Check Xcode console for debug messages

### KEY_OFF not working
- Ensure you're using the `:OFF` suffix: `KEYCUT ME:1:1:OFF`
- Check that the keyer number matches

---

## RossTalk Protocol Reference

### Command Format
All commands are ASCII text terminated with `\r\n` (CR/LF)

### Commands Supported

| Command | Format | Example |
|---------|--------|---------|
| MECUT | `MECUT ME:<me>` | `MECUT ME:1` |
| MEAUTO | `MEAUTO ME:<me>` | `MEAUTO ME:1` |
| KEYCUT | `KEYCUT ME:<me>:<keyer>[:OFF]` | `KEYCUT ME:1:2:OFF` |
| KEYAUTO | `KEYAUTO ME:<me>:<keyer>[:OFF]` | `KEYAUTO ME:1:1` |
| SELECT | `SELECT <dest>:<source>` | `SELECT PGM:1:IN:3` |
| XPT | `XPT <level> <dest> <src>` | `XPT vid 1 3` |
| SALVO | `SALVO <number>` | `SALVO 1` |
