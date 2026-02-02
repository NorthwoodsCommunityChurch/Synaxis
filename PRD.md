# Product Requirements Document: Synaxis

**Version:** 2.0 (Clarified Requirements)
**Created:** January 29, 2026
**Original Author:** Seth Potter
**Platform:** macOS (SwiftUI native application)
**Target OS:** macOS 15 Sequoia (15.6.1)

---

## 1. Product Overview

**Synaxis** is a macOS desktop application that bridges live broadcast production equipment with post-production editing. During a live multi-camera event, the video director switches cameras, brings keyers up and down for graphics from ProPresenter, and Blackmagic HyperDecks record ISO feeds. After the event, an editor must manually review all footage and reconstruct the sequence of camera cuts, graphics overlays, and transitions. This app eliminates that manual work by sitting on the network, watching everything in real time, timestamping every event, and exporting an Adobe Premiere-compatible XML timeline — a pre-built rough cut ready for editing.

### Target Users
- Church and broadcast production teams (Northwoods Community Church)
- Post-production editors working with multi-camera live event footage

### Problem Statement
After a live multi-camera production, an editor must manually review footage to recreate the sequence of camera cuts, graphics overlays, and transitions. This is time-consuming and error-prone. Synaxis automates this by capturing the switching data in real time and generating an editable timeline.

### Key Terminology
- **Video Director** — the person operating the video switcher during a live event (not "TD" or "Technical Director" in this context)
- **ISO** — isolated recording of an individual camera feed
- **ME** — Mix/Effects bus on the production switcher
- **MiniME** — a simplified ME available on Carbonite switchers
- **Keyer** — a layer on the switcher that composites graphics (e.g., ProPresenter output) over the program video

---

## 2. Hardware Profile

This is the specific equipment the app targets:

| Equipment | Model | Quantity | Role |
|---|---|---|---|
| Production Switcher | Ross Ultrix Carbonite | 1 | Video switching, 2 MEs + 1 MiniME |
| Cameras | Various | 3 | Live camera sources |
| Recorder | Blackmagic HyperDeck Extreme 8K | 1 | Records ISOs + program feed to network storage |
| Presentation | ProPresenter 7 (v21.x) | 1+ | Lyrics, scripture, announcements — feeds a keyer (supports multiple machines) |
| Edit System | Adobe Premiere v26.0 | 1 | Post-production NLE |

### HyperDeck Recording Setup
The HyperDeck Extreme 8K supports 4-channel simultaneous SDI recording via its 4x 12G-SDI inputs. The current setup:
- **Channel 1:** Camera 1 ISO
- **Channel 2:** Camera 2 ISO
- **Channel 3:** Camera 3 ISO
- **Channel 4:** Program feed

The HyperDeck records directly to a network storage server (via 10GbE) that editors access directly. The recorded files ARE the source media for the Premiere timeline.

### Timecode
The HyperDeck is the intended timecode source (pending final confirmation). It supports external timecode via XLR input, embedded SDI timecode, or internal preset timecode. The app should support selecting the timecode source with HyperDeck as the default.

---

## 3. Industry & Protocol Context

### 3.1 Adobe Premiere (v26.0, January 2026)

Adobe dropped the "Pro" suffix in v26.0. Key facts for this project:

- **XML format**: Premiere reads/writes **xmeml version 4** (FCP 7-era XML). This is the only XML schema Premiere natively imports. It does NOT support FCPXML (Final Cut Pro X format).
- **xmeml version 5** (FCP 7.0) adds `anchoroffset` for speed-change accuracy. Targeting v4 or v5 is correct.
- **OpenTimelineIO (OTIO)**: Now officially supported in v26.0. A simpler, modern alternative worth considering as a second export target.
- **UXP scripting**: New JavaScript-based extensibility platform. ExtendScript support ends September 2026.
- **Multicam features**: Premiere can sync multi-camera sequences by timecode, in/out points, or audio waveforms.
- **Minimum macOS**: Sonoma (14) required for v26.0.

### 3.2 Ross Hardware Ecosystem

#### Ross Ultrix
A hyperconverged media processing platform — combines signal routing, processing, multiviewing, and audio in a single chassis (1-12 RU frames, up to 288x288 matrix). Software-defined via licenses. Supports SDI, ST 2110, NDI, Dante, and MADI simultaneously.

#### Ross Carbonite
A mid-size production switcher family. Current flagship is the Carbonite Ultra (1 RU, up to 3 MEs, 5 keyers per ME, UltraChrome chroma-keying, RAVE audio mixer).

#### Ultrix Carbonite (Combined Product — Target Hardware)
An Ultrix frame with SDPE (Software-Defined Production Engine) blades running Carbonite switcher software. Each SDPE blade provides up to 2 MEs with 7 keyers per ME. The Northwoods system has 2 MEs + 1 MiniME.

### 3.3 TSL 5.0 Protocol (Primary Switcher Integration)

**Decision: TSL 5.0 was chosen over RossTalk for switcher integration.** The Ultrix Carbonite supports both, but TSL 5.0 provides the event-push capability that RossTalk lacks. This architecture is proven working in the existing iPhone Tally app.

#### Architecture
The Mac app runs as a **TCP client** that connects TO the Carbonite's TSL output port. The Carbonite acts as the server, streaming tally/label data to any connected clients. The app is configured with the Carbonite's IP address and TSL port.

#### Packet Format (TSL 5.0)
```
Bytes 0-1:   PBC (Packet Byte Count) - little endian, excludes itself
Byte 2:      Version (0x00 for TSL 5.0)
Byte 3:      Flags
Bytes 4-5:   Screen index - little endian
Bytes 6-7:   Index (display/source index) - little endian, 1-based
Bytes 8-9:   Control (tally data) - little endian
Bytes 10-11: Text length - little endian
Bytes 12+:   Text (UTF-8 first, fallback to UTF-16LE)
```

Total message length = PBC + 2 (PBC doesn't include its own 2 bytes)

#### Control Byte Tally Extraction
```
Bits 0-1: Program tally    0=Off, 1=Red, 2=Green, 3=Amber
Bits 2-3: Preview tally    0=Off, 1=Red, 2=Green, 3=Amber
Bits 4-5: LH Tally         0=Off, 1=Red, 2=Green, 3=Amber
Bits 6-7: Brightness        0-3
```

**NOTE:** The bit mapping above matches what the Carbonite actually sends, confirmed by the working tally app implementation. This may differ from the TSL 5.0 spec document ordering.

#### Label Format from Carbonite
`source-index:bus-label:source-label`
Example: `0:ME1PGM:In 001` = source 0, ME1 Program bus, input "In 001"

Bus labels include: PGM, PV, CLN, ME1PGM, ME1PRV, ME1CLN, ME2PGM, ME2PRV, Aux 1-8, MiniME buses.

**Important:** Only buses whose label contains "PGM" or "PROGRAM" represent actual director cuts. The app filters out preview, clean, aux, and other non-program bus changes to avoid false cut events. Per-bus debouncing (300ms) prevents duplicate cuts during transitions.

#### Protocol Detection (TSL 5.0 vs 3.1)
```
PBC between 10 and 1000 + version byte == 0x00 → TSL 5.0
PBC > 1000 → TSL 3.1 fallback (fixed 18-byte messages)
```

#### Key Constants
| Constant | Value |
|----------|-------|
| TSL listener port | 5201 |
| TSL 5.0 version byte | 0x00 |
| TSL 3.1 message size | 18 bytes fixed |
| TSL 5.0 min PBC | 10 |
| TSL 5.0 max PBC | 1000 |
| Tally 1 (Program) mask | 0x03 (bits 0-1) |
| Tally 2 (Preview) mask | 0x0C >> 2 (bits 2-3) |
| TSL index | 1-based |

#### Carbonite Configuration (DashBoard)
The Carbonite must be configured to output TSL data on a TCP port. The Mac app connects to this port as a client.
1. DashBoard > Configuration > Devices
2. Add/configure TSL UMD output (Driver: TSL 5)
3. Set the port the Carbonite listens on (e.g., 5201)
4. In the Mac app, enter the Carbonite's IP address and port under Settings > Connections > TSL

#### What Synaxis Needs Beyond Tally
The iPhone Tally app only needs binary program/preview state per source. Synaxis needs:
- **Which source** went to program on which ME (not just "is this source on program?")
- Track keyer on/off states across all MEs
- Track source selections over time for timeline reconstruction
- Parse label text to extract bus name and source name
- Correlate TSL source indices with camera assignments

This is achieved by monitoring ALL TSL messages and building a full state model of all buses.

### 3.4 RossTalk Protocol (Reference Only)

RossTalk is primarily a command-send protocol, NOT an event-push protocol. It remains documented here for reference but is NOT used for the primary integration.

| Property | Detail |
|---|---|
| Transport | TCP |
| Port | 7788 |
| Encoding | ASCII, case-sensitive |
| Direction | Send-only by default |

RossTalk may be used in the future for sending commands TO the switcher (e.g., triggering custom controls), but not for receiving state changes.

### 3.5 Blackmagic HyperDeck Protocol

Two control interfaces available:

**Ethernet Protocol (TCP 9993):**
- Text-based, line-terminated with `\r\n` (not `\n`)
- On connect: `500 connection info:` header
- Async notifications via `notify:` command
- Commands: `play`, `record`, `stop`, `goto`, `clips get`, `transport info`, `slot info`, `device info`

**REST API (HTTP):**
- Base URL: `http://{IP}/control/api/v1/`
- WebSocket events: `ws://{IP}/control/api/v1/event/websocket`
- Transport, system, media, timeline control endpoints

### 3.6 ProPresenter API

- HTTP REST + chunked streaming endpoints
- **TCP/IP API port** — found in Pro7 Settings > Network > TCP/IP section (user-configured, no universal default)
- **No authentication required** for HTTP API (accessible to all devices on network)
- **ProPresenter Remote** uses the main Port (e.g. 57131) + password — separate from the API port
- WebSocket legacy protocol (pre-7.9) DOES require password authentication
- Chunked HTTP is the official real-time monitoring mechanism
- Key streaming endpoint: `/v1/status/slide` for slide change detection
- Aggregator endpoint: `/v1/status/updates` for efficient multi-stream monitoring
- Current version: 21.0.1 (numbering changed: 7.x → 17 → 18 → 19 → 20 → 21)

---

## 4. System Architecture

### Tech Stack
| Component | Technology |
|---|---|
| Language | Swift |
| UI Framework | SwiftUI |
| State Management | @Observable macro (Swift 5.9+) |
| Networking | Network.framework (TCP/TSL), URLSession (HTTP) |
| Logging | os.log / Logger with categories |
| Persistence | UserDefaults, JSON file export |
| Build System | Xcode project |
| Architecture | MVVM with split view models |
| Target OS | macOS 15 Sequoia (15.6.1) |

### Service Layer
| Service | Protocol | Default Port | Direction | Purpose |
|---|---|---|---|---|
| TSLClient | TCP (binary) | 5201 | Outbound (client) | Connects to Carbonite's TSL output for tally/bus state |
| ProPresenterClient | HTTP REST + chunked | User-configured (TCP/IP port from Pro7 Network settings) | Outbound (client) | Monitors slide changes, presentation state |
| HyperDeckClient | TCP (text) | 9993 | Outbound (client) | Controls recording, tracks timecode/transport |
| EventLogger | Internal | — | — | Aggregates events into sessions |
| PremiereXMLGenerator | Internal | — | — | Produces xmeml v4 output |

---

## 5. Functional Requirements

### 5.1 Device Connections

**FR-1: TSL 5.0 Switcher Integration**
- Connect as a TCP client to the Carbonite's TSL output port using Network.framework (`NWConnection`)
- Configurable host IP and port (default 5201)
- Auto-detect TSL 5.0 vs TSL 3.1 protocol
- Automatic reconnection with exponential backoff on connection loss
- Parse all TSL messages: extract source index, control byte (program/preview tally), and label text
- Build and maintain a full state model of all buses (ME1 PGM, ME1 PVW, ME2, MiniME, DSKs, Aux buses)
- Parse Carbonite label format (`source-index:bus-label:source-label`) to identify bus and source
- Detect state changes (source went to program, keyer on/off) by comparing current vs previous state
- Handle TCP stream buffering (messages may arrive fragmented or concatenated)
- Log raw hex data for diagnostics

**FR-2: Source Filtering**
- Monitor ALL TSL messages from all buses
- Only emit program cut events from buses whose label contains "PGM" or "PROGRAM" (filters out preview, clean, aux, and MiniME buses)
- Per-bus debounce (300ms) prevents duplicate cuts during video transitions
- Provide UI option to configure which sources are "cameras" (map TSL source indices to camera names)
- Filter the timeline output to only include configured camera sources
- XML export uses fallback camera assignments for any unmatched TSL source indices (no cuts are silently dropped)

**FR-3: ProPresenter Integration**
- Connect via HTTP REST API to ProPresenter (TCP/IP port from Pro7 Settings > Network, no authentication for HTTP)
- Use chunked HTTP streaming on `/v1/status/slide` for real-time slide change detection
- Capture: presentation name, slide index, slide text content
- Emit events on each slide transition
- Configurable host and port
- **Keyer assignment:** User configures which ME and which keyer number ProPresenter feeds
- Automatic reconnection with exponential backoff on connection loss

**FR-4: Blackmagic HyperDeck Integration**
- Connect via Ethernet Protocol over TCP port 9993
- Use `\r\n` line termination for all commands
- Subscribe to async notifications: `notify: transport: true slot: true configuration: true`
- Track timecode, transport state (record/play/stop), and clip list
- **Start/stop recording** from the app (send `record` and `stop` commands)
- Use HyperDeck as timecode source (configurable, with fallback to system clock)
- Match clip names to camera inputs via configurable prefix patterns
- Auto-populate camera file paths from matched clips
- Automatic reconnection with exponential backoff on connection loss

### 5.2 Event Capture

**FR-5: Production Event Logging**
- Capture events of types: `programCut`, `transition`, `keyerOn`, `keyerOff`, `slideChange`, `fadeToBlack`, `recordStart`, `recordStop`, `connectionChange`
- Timestamp each event from the timecode source (HyperDeck preferred, system clock fallback)
- Store: source index, source name, bus name, ME number, keyer number, slide text, presentation name
- Build a running timeline of which camera was on program at every point in time
- Display events in a real-time scrolling log

**FR-6: Session Management**
- Start/stop recording sessions with a user-defined session name
- App runs unattended during events — no interaction required after start
- Support back-to-back sessions (rehearsals followed by shows) without restarting the app
- "New Session" resets the event log but keeps all configuration
- Store all events, assignments, and metadata within a session
- Persist session data as JSON for import/export
- Track frame rate, timecode start, and resolution per session

### 5.3 Configuration

**FR-7: Camera Assignments**
- Map TSL source indices to camera names (e.g., TSL index 1 → "Camera 1")
- Assign video file paths per camera (the HyperDeck ISO recordings on the storage server)
- Support file dialog selection for video files
- Persist assignments across app sessions

**FR-8: Keyer Assignments**
- Configure which ME and which keyer number ProPresenter feeds (user-selectable)
- Map additional keyers to other graphics sources if needed
- Support multiple keyer configurations

**FR-9: ProPresenter Configuration**
- All ProPresenter settings consolidated in a dedicated ProPresenter sidebar tab (not in Settings)
- **API Connection:** Configure host IP and TCP/IP API port (from Pro7 Settings > Network > TCP/IP) for slide status monitoring via HTTP REST
- **Remote Connection:** Optional remote control port (main Port from Pro7 Settings > Network) and password for ProPresenter Remote protocol
- No password needed for HTTP API (note: Remote protocol does need password)
- Associate with a keyer assignment (which ME, which keyer)
- Test connection button
- ProPresenter config stored in `AssignmentStore` (separate from `SettingsManager`)

**FR-10: HyperDeck Configuration**
- Configure IP address and port (default: 9993)
- Map HyperDeck recording channels to camera inputs (Channel 1 → Camera 1, etc.)
- Configure recording codec/format preferences
- Configure clip prefix for filename matching
- Test connection button

**FR-11: Project Settings**
- Configurable frame rate: 23.976, 24, 25, 29.97, 30, 50, 59.94, 60 fps
- Configurable resolution (default 1920x1080)
- Configurable start timecode with format validation (`HH:MM:SS:FF`)
- Timecode source selection: HyperDeck (default), system clock, manual preset
- Drop-frame toggle (required for 29.97 and 59.94)

**FR-12: Export Settings**
- Configurable default export path
- Token-based file naming patterns
- Auto-export on session stop (optional)

### 5.4 Export

**FR-13: Premiere XML Export**
- Generate **xmeml version 4** format
- **Timeline track structure:**
  - **V1:** Program cut (reconstructed from TSL data — which camera was on ME1 PGM at each moment)
  - **V2:** Camera 1 ISO (full-length clip)
  - **V3:** Camera 2 ISO (full-length clip)
  - **V4:** Camera 3 ISO (full-length clip)
  - **V5:** Graphics/ProPresenter track (clips for each slide change period)
- Include `<format>` and `<samplecharacteristics>` elements with width/height/codec
- Calculate clip in/out points as **source-relative** positions
- Correctly handle drop-frame timecode for 29.97fps and 59.94fps
- Set `<ntsc>TRUE</ntsc>` for 23.976, 29.97, and 59.94 fps
- **Markers:** Add timeline markers for keyer on/off events AND ProPresenter slide changes (in addition to the graphics track clips)
- Use proper XML generation (XMLDocument, not string concatenation)
- Audio: include paired audio tracks (follow video — each video track gets a corresponding audio track). Detailed audio routing is TBD.

**FR-14: Graphics Track**
- Each ProPresenter slide change creates a clip on the graphics track (V5)
- Clip duration = time from this slide change to the next slide change
- Clip metadata includes: presentation name, slide text, slide index
- **Future enhancement:** Associate actual ProPresenter exported media (images/video) with these clips. For now, use placeholder clips with descriptive names.

**FR-15: OTIO Export (Future)**
- Generate OpenTimelineIO format as an alternative export target
- Supported natively in Adobe Premiere v26.0+

**FR-16: XML Preview**
- Display generated XML in-app before export
- Show timeline statistics: clip count, duration, track count, marker count

**FR-17: Session JSON Export/Import**
- Export full session data as JSON
- Import previously saved sessions for re-export or review
- Show meaningful error messages for corrupted imports

### 5.5 User Interface

**FR-18: Navigation Layout**
- `NavigationSplitView` two-column (sidebar + detail)
- Sidebar with two sections:
  - **Monitor:** Dashboard, Event Log, Diagnostics
  - **Configuration:** Assignments (cameras + keyers), ProPresenter, HyperDeck, Settings
- Toolbar: Recording controls, HyperDeck record start/stop, export actions
- Settings embedded in sidebar (not a separate Cmd+Comma scene)

**FR-19: Dashboard**
- Connection status indicators for all configured devices (TSL listener, ProPresenter, HyperDeck)
- Real-time event feed with auto-scroll
- Current timecode display (from HyperDeck)
- Current program source display (from TSL)
- Current ProPresenter slide display

**FR-20: Recording Controls**
- Toolbar with session start/stop toggle
- HyperDeck record start/stop button
- Animated recording indicator (pulsing red dot)
- Session name input field
- Export buttons: Preview XML, Export Premiere XML, Export Session JSON, Import Session
- Keyboard shortcuts for start/stop and export

**FR-21: Settings View (Sidebar Tab)**
- Embedded in the sidebar as a tab (not a separate Cmd+Comma scene)
- Tabbed layout within the detail pane:
  - **Connections:** TSL host/port/enable, HyperDeck host/port/enable, Connect All / Disconnect All (ProPresenter settings are in the dedicated ProPresenter tab)
  - **Project:** Frame rate, resolution, timecode source, start timecode, drop-frame
  - **Export:** Default export path, filename pattern, auto-export toggle
  - **Timecode:** Timecode source selection, drop-frame, live timecode status

**FR-22: Diagnostics**
- Connection debug information with correct protocol labels
- Raw TSL hex dump viewer
- ProPresenter API response viewer
- HyperDeck transport state viewer
- Recent event list for troubleshooting
- Test event generation buttons for development/QA

---

## 6. Non-Functional Requirements

**NFR-1: Unattended Operation**
- The app must run reliably for the duration of a live event (1-4 hours) without user interaction
- No modal dialogs or alerts that would block event capture
- All errors handled gracefully with logging, not crashes

**NFR-2: Connection Robustness**
- Automatic reconnection with exponential backoff for all three connections (TSL, ProPresenter, HyperDeck)
- No data loss during brief network interruptions
- Connection state changes logged as events
- Recovery from: network cable disconnects, device reboots, Wi-Fi drops

**NFR-3: Performance**
- Sub-second event capture latency
- Handle sustained event rates from live production switching
- Efficient view rendering (avoid per-row allocations in event log)
- Support sessions with 10,000+ events without UI degradation

**NFR-4: Persistence**
- All settings survive app restart
- Camera and keyer assignments persist
- First-launch defaults work correctly (no UserDefaults.bool() zero-value bugs)

**NFR-5: Compatibility**
- macOS 15 Sequoia (15.6.1) — primary target
- Exported XML: xmeml version 4 validated against Premiere v26.0 import
- Ross Ultrix Carbonite via TSL 5.0 (client connecting to Carbonite's TSL port, default 5201)
- ProPresenter 21.x REST API (TCP/IP port from Pro7 Network settings, no auth)
- Blackmagic HyperDeck Extreme 8K Ethernet protocol (port 9993, `\r\n`)

**NFR-6: Logging & Diagnostics**
- Structured logging via `os.log` / `Logger` with categories:
  - `TSL` — all TSL protocol activity
  - `ProPresenter` — API requests and responses
  - `HyperDeck` — protocol commands and transport state
  - `Session` — event capture and session lifecycle
  - `Export` — XML generation
  - `UI` — user actions
- Visible in Console.app with subsystem filtering
- In-app DiagnosticsView for live monitoring
- Session event log persisted with session data

---

## 7. Data Model

### ProductionEvent
| Field | Type | Description |
|---|---|---|
| id | UUID | Unique event identifier |
| timestamp | Date | Capture time (from timecode source) |
| timecode | String | Formatted timecode at event time |
| type | EventType | programCut, transition, keyerOn, keyerOff, slideChange, fadeToBlack, recordStart, recordStop, connectionChange |
| sourceIndex | Int? | TSL source index |
| sourceName | String? | Human-readable source name (from TSL label or camera assignment) |
| busName | String? | Bus identifier (ME1PGM, ME2PVW, etc.) |
| meNumber | Int? | ME bus number |
| keyerNumber | Int? | Keyer index |
| slideText | String? | ProPresenter slide content |
| presentationName | String? | ProPresenter presentation name |
| slideIndex | Int? | ProPresenter slide index |

### ProductionSession
| Field | Type | Description |
|---|---|---|
| id | UUID | Session identifier |
| name | String | User-defined session name |
| startTime | Date | Session start timestamp |
| endTime | Date? | Session end timestamp |
| events | [ProductionEvent] | All captured events |
| cameraAssignments | [CameraAssignment] | TSL index to camera mappings |
| keyerAssignments | [KeyerAssignment] | Keyer to graphics mappings |
| proPresenterConfigs | [ProPresenterConfig] | ProPresenter machine configurations (supports multiple) |
| frameRate | Double | Project frame rate |
| resolution | Resolution | Width x height |
| startTimecode | String | Session start timecode |
| timecodeSource | TimecodeSource | HyperDeck, systemClock, or manual |

### CameraAssignment
| Field | Type | Description |
|---|---|---|
| tslIndex | Int | TSL source index (1-based) |
| name | String | Display name (e.g., "Camera 1") |
| fileURL | URL? | Path to ISO recording on storage server |
| hyperDeckChannel | Int? | HyperDeck recording input (1-8) |

### KeyerAssignment
| Field | Type | Description |
|---|---|---|
| meNumber | Int | ME number (1, 2, or MiniME) |
| keyerNumber | Int | Keyer index on that ME |
| label | String | Description (e.g., "ProPresenter Lower Thirds") |
| source | KeyerSource | ProPresenter, graphics folder, or other |

### ProPresenterConfig
| Field | Type | Description |
|---|---|---|
| id | UUID | Unique identifier for this machine |
| name | String | Display name (e.g., "Main ProPresenter", "Lyrics Machine") |
| host | String | ProPresenter IP address |
| apiPort | Int | TCP/IP API port (from Pro7 Settings > Network > TCP/IP) |
| enabled | Bool | Whether API connection is enabled |
| remotePort | Int | Main network port (from Pro7 Settings > Network, top-level Port field) |
| remotePassword | String | ProPresenter Remote password |
| remoteEnabled | Bool | Whether remote connection is enabled |
| meNumber | Int | Which ME the keyer is on |
| keyerNumber | Int | Which keyer on that ME |

Multiple ProPresenter machines are supported. Each machine has its own connection, keyer assignment, and name. Events from each machine are stamped with the machine name.

---

## 8. Timeline Structure (Premiere XML Output)

The exported xmeml produces a multi-track timeline:

```
V1: ┌─Cam2─┐┌──Cam1──┐┌─Cam3─┐┌──Cam1──┐┌─Cam2─┐   ← Program cut (from TSL)
V2: ┌─────────────── Camera 1 ISO ──────────────────┐  ← Full-length ISO
V3: ┌─────────────── Camera 2 ISO ──────────────────┐  ← Full-length ISO
V4: ┌─────────────── Camera 3 ISO ──────────────────┐  ← Full-length ISO
V5: ┌─Song─┐┌Scrip┐┌──Song──┐┌─Announce─┐            ← Graphics (ProPresenter)
A1: ┌─────────────── Program Audio ─────────────────┐  ← Paired with V1
A2: ┌─────────────── Camera 1 Audio ────────────────┐  ← Paired with V2
A3: ┌─────────────── Camera 2 Audio ────────────────┐  ← Paired with V3
A4: ┌─────────────── Camera 3 Audio ────────────────┐  ← Paired with V4

Markers: ▼ Keyer On  ▽ Keyer Off  ◆ Slide Change
```

### V1 — Program Cut
Reconstructed from TSL data. Each time the program source changes on the monitored bus (e.g., ME1 PGM), a new clip is placed on V1 using the corresponding camera's ISO recording, with in/out points matching the switch times.

### V2-V4 — Camera ISOs
Full-length clips from the HyperDeck recordings. These are reference tracks — the editor can see all angles and easily adjust the rough cut.

### V5 — Graphics Track
Each ProPresenter slide change creates a clip. Duration = time between slide changes. Initially uses placeholder clips with descriptive names; future enhancement to link actual exported ProPresenter media.

### Markers
Both keyer events (on/off) and ProPresenter slide changes are placed as timeline markers with descriptive text, in addition to the graphics track clips.

---

## 9. Default Configuration

| Setting | Default Value |
|---|---|
| TSL Host | (empty — user configures Carbonite IP) |
| TSL Port | 5201 |
| ProPresenter Host | (empty — user configures) |
| ProPresenter API Port | (empty — user enters TCP/IP port from Pro7 Network settings) |
| ProPresenter Remote Port | (empty — user enters main Port from Pro7 Network settings) |
| HyperDeck IP | (empty — user configures) |
| HyperDeck Port | 9993 |
| Frame Rate | 29.97 fps |
| Resolution | 1920x1080 |
| Start Timecode | 01:00:00:00 |
| Timecode Source | HyperDeck |
| Drop Frame | true (for 29.97) |

---

## 10. Typical Workflow

```
┌─────────────┐    ┌──────────────┐    ┌───────────────┐
│   SETUP     │───▶│   CAPTURE    │───▶│  POST-PROD    │
│             │    │              │    │               │
│ • Assign    │    │ • Start      │    │ • Stop        │
│   cameras   │    │   session    │    │   session     │
│ • Assign    │    │ • Start      │    │ • Preview XML │
│   keyers    │    │   HyperDeck  │    │ • Export to   │
│ • Configure │    │   recording  │    │   Premiere    │
│   devices   │    │ • Events     │    │ • Open in     │
│ • Set frame │    │   auto-log   │    │   editor      │
│   rate/res  │    │ • Runs       │    │               │
│             │    │   unattended │    │               │
└─────────────┘    └──────────────┘    └───────────────┘
```

1. **Setup (before event):** Configure camera assignments (map TSL indices to camera names and ISO file paths), configure ProPresenter keyer assignment (which ME, which keyer), set project frame rate and resolution, verify all connections show green in Dashboard.

2. **Capture (during event):** Start a session, start HyperDeck recording. The video director operates the Ultrix Carbonite normally. The app sits on the network, receives TSL data from the Carbonite and slide changes from ProPresenter, timestamps everything, and builds a complete event log. No operator interaction needed.

3. **Post-Production (after event):** Stop the session and HyperDeck recording. Preview the generated XML timeline. Export the xmeml file. Open in Premiere — the editor gets a rough cut with all camera switches pre-placed on V1, all ISOs on V2-V4, and ProPresenter graphics on V5, with markers at every keyer and slide event.

---

## 11. Critical Bugs (Current Codebase)

These issues were identified in the v1.0 codebase. Many are resolved by the v2.0 architecture rewrite (TSL 5.0 replacing RossTalk, split ViewModels, XMLDocument-based generator).

### P0 — Will cause crashes or data loss

| # | File | Issue | Status |
|---|---|---|---|
| 1 | `ProPresenterClient.swift` | Force-unwrap on `urlSession!` — crashes on disconnect during async | Open |
| 2 | `RossTalkClient.swift` | Force-unwrap on port — crashes if port is 0 | Superseded (replacing with TSLClient) |
| 3 | `HyperDeckClient.swift` | Force-unwrap on port — crashes if port is 0 | Open |
| 4 | `AppCoordinator.swift` | Camera/keyer assignments not saved to UserDefaults | Open |
| 5 | `AppCoordinator.swift` | `carboniteEnabled` defaults to false from `UserDefaults.bool()` on first launch | Open |

### P1 — Incorrect behavior

| # | File | Issue | Status |
|---|---|---|---|
| 6 | `HyperDeckClient.swift` | Commands use `\n` instead of `\r\n` — silently ignored | Open |
| 7 | `PremiereXMLGenerator.swift` | Drop-frame timecode not implemented | Open |
| 8 | `PremiereXMLGenerator.swift` | 59.94fps missing from NTSC check | Open |
| 9 | `PremiereXMLGenerator.swift` | Clip in/out use absolute positions, not source-relative | Open |
| 10 | `PremiereXMLGenerator.swift` | Missing `<format>` and `<samplecharacteristics>` | Open |
| 11 | `PremiereXMLGenerator.swift` | Graphics clips point to directories, not files | Open |
| 12 | `PremiereXMLGenerator.swift` | No audio tracks generated | Open |
| 13 | `RossTalkClient.swift` | MECUT/MEAUTO have no source input | Superseded (TSL provides source info) |
| 14 | `ProPresenterClient.swift` | Password never sent in API requests | Resolved (HTTP API needs no auth) |
| 15 | `ProPresenterClient.swift` | Wrong port (57131 instead of 1025) | Resolved — ports are now user-configured, no hardcoded defaults |
| 16 | `AppCoordinator.swift` | `autoExportOnStop` never triggered | Open |
| 17 | `AppCoordinator.swift` | Export filename tokens only in preview, not actual export | Open |

### P2 — Reliability / UX

| # | File | Issue | Status |
|---|---|---|---|
| 18 | All TCP clients | No automatic reconnection | Open |
| 19 | `AppCoordinator.swift` | `connectProPresenter` creates duplicate clients | Open |
| 20 | `ProPresenterClient.swift` | Slide detection only compares index, misses re-triggers | Open |
| 21 | `HyperDeckClient.swift` | Clip name parsing breaks on spaces | Open |
| 22 | `SettingsView.swift` | Timecode source selection is UI-only | Open |
| 23 | `RecordingControlsView.swift` | Pulse animation declared but never activated | Open |
| 24 | `ConnectionStatusView.swift` | Disconnect button uses connect icon | Open |
| 25 | `DiagnosticsView.swift` | ProPresenter label shows `ws://` instead of `http://` | Open |
| 26 | `EventLogView.swift` | DateFormatter created per row render | Open |
| 27 | `ContentView.swift` | Tab selection uses magic integers | Open |
| 28 | No accessibility labels on status indicators or controls | Open |

---

## 12. Architectural Changes

### 12.1 Replace RossTalkClient with TSLClient
The existing `RossTalkClient.swift` is replaced entirely by a new `TSLClient.swift` that:
- Connects as a TCP client to the Carbonite's TSL output port using `NWConnection` (Network.framework)
- The Carbonite is the server; the app connects to it (not the other way around)
- Configurable host IP and port (default 5201)
- Implements TSL 5.0 parsing with TSL 3.1 fallback
- Uses a `Data` buffer for TCP stream reassembly
- Builds and maintains a full bus state model
- Automatic reconnection with exponential backoff (2, 4, 8, 16, 30s cap)

### 12.2 Split AppCoordinator
The 525-line god object splits into:
- **ConnectionManager** — device connection lifecycle, reconnection logic, connection state
- **AssignmentStore** — camera, keyer, ProPresenter, HyperDeck assignment CRUD and persistence
- **SettingsManager** — UserDefaults with correct first-launch defaults
- **SessionManager** — session start/stop, event aggregation, export triggers

### 12.3 Use @Observable
Replace `ObservableObject` / `@Published` pattern with `@Observable` macro (Swift 5.9+, available on macOS 14+). This eliminates the 30+ `@Published` property problem and gives fine-grained observation.

### 12.4 Use XMLDocument for XML Generation
Replace string concatenation with `Foundation.XMLDocument` for well-formed, properly escaped output.

### 12.5 Structured Logging
Replace `print()` statements with `os.log` / `Logger` using subsystem `com.northwoods.touchdrive` and per-service categories.

---

## 13. Project Organization (Git Release)

```
Synaxis/
├── .gitignore
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CREDITS.md                    # Attribution for referenced work
├── PRD.md
├── docs/                         # Protocol and API references
│   ├── README.md
│   ├── HyperDeckEthernetProtocol.pdf
│   ├── RESTAPIForHyperDeck.pdf
│   ├── RossTalk-Commands.pdf
│   ├── TSL-UMD-Protocol-Spec.pdf
│   ├── ProPresenter-Official-OpenAPI.json
│   ├── ProPresenter-OpenAPI-Spec.json
│   ├── HyperDeck-Extreme-8K-Reference.md
│   ├── ProPresenter-API-Reference.md
│   ├── TSL5-Implementation-Notes.md
│   └── macOS-Tahoe-Design-Reference.md
├── Touchdrive to Premiere/
│   ├── Touchdrive to Premiere.xcodeproj/
│   ├── Touchdrive to Premiere/
│   │   ├── App/
│   │   │   └── Touchdrive_to_PremiereApp.swift
│   │   ├── Models/
│   │   │   ├── ProductionEvent.swift
│   │   │   ├── ProductionSession.swift
│   │   │   ├── CameraAssignment.swift
│   │   │   ├── KeyerAssignment.swift
│   │   │   ├── ProPresenterConfig.swift
│   │   │   └── AppError.swift
│   │   ├── ViewModels/
│   │   │   ├── ConnectionManager.swift
│   │   │   ├── AssignmentStore.swift
│   │   │   ├── SettingsManager.swift
│   │   │   └── SessionManager.swift
│   │   ├── Services/
│   │   │   ├── TSLClient.swift
│   │   │   ├── ProPresenterClient.swift
│   │   │   ├── HyperDeckClient.swift
│   │   │   ├── EventLogger.swift
│   │   │   └── PremiereXMLGenerator.swift
│   │   ├── Views/
│   │   │   ├── Dashboard/
│   │   │   │   └── DashboardView.swift
│   │   │   ├── Recording/
│   │   │   │   └── RecordingControlsView.swift
│   │   │   ├── EventLog/
│   │   │   │   └── EventLogView.swift
│   │   │   ├── Configuration/
│   │   │   │   ├── CameraAssignmentView.swift
│   │   │   │   ├── KeyerAssignmentView.swift
│   │   │   │   ├── ProPresenterConfigView.swift
│   │   │   │   └── HyperDeckConfigView.swift
│   │   │   ├── Settings/
│   │   │   │   └── SettingsView.swift
│   │   │   ├── Diagnostics/
│   │   │   │   ├── DiagnosticsView.swift
│   │   │   │   ├── ConnectionDiagnosticCard.swift
│   │   │   │   └── EventDiagnosticRow.swift
│   │   │   ├── Export/
│   │   │   │   └── XMLPreviewView.swift
│   │   │   ├── Shared/
│   │   │   │   └── ConnectionStatusView.swift
│   │   │   └── ContentView.swift
│   │   ├── Utilities/
│   │   │   ├── TimecodeHelpers.swift
│   │   │   └── TransportStatusHelpers.swift
│   │   ├── Resources/
│   │   │   └── Assets.xcassets/
│   │   └── Touchdrive_to_Premiere.entitlements
│   └── Touchdrive to PremiereTests/
│       ├── XMLGeneratorTests.swift
│       ├── TSLParserTests.swift
│       ├── HyperDeckParserTests.swift
│       ├── TimecodeTests.swift
│       └── EventLoggerTests.swift
├── .github/
│   └── workflows/
│       └── build.yml
└── Tools/
    └── ross_simulator.py
```

### CREDITS.md Structure
```markdown
# Credits

## Synaxis
Created by Northwoods Community Church

### Original Code
- Seth Potter — initial implementation

### Protocol References
- TSL Products Ltd — TSL UMD Protocol v5.0 specification
- Blackmagic Design — HyperDeck Ethernet Protocol, REST API
- Renewed Vision — ProPresenter OpenAPI specification
- Ross Video — RossTalk command reference

### Community Resources
- Jeff Mikels — ProPresenter API community documentation
  https://github.com/jeffmikels/ProPresenter-API

### Tools
- Claude Code (Anthropic) — development assistance
```

---

## 14. Open Items (TBD)

| Item | Status | Notes |
|---|---|---|
| Timecode source | Leaning HyperDeck | User to confirm after testing |
| Audio track routing | TBD | Currently: paired audio follows video. May need separate audio routing config. |
| ProPresenter media export | Future enhancement | Export slides as images/video from Pro 7 and link to graphics track clips |
| OTIO export | Future | Second export format for Premiere v26.0+ |
| UXP plugin | Future | Direct Premiere integration via scripting |

---

## 15. Future Considerations

- **OTIO export** as a second format target (Premiere v26.0+)
- **UXP plugin** for direct Premiere integration
- **ProPresenter media export** — export slides/presentations as media and associate with graphics track clips
- **Multiple HyperDecks** — scale to separate decks per camera
- **NMOS IS-04/IS-05** for IP-based Ultrix discovery
- **macOS 26 (Tahoe)** — adopt Liquid Glass design language when targeting macOS 26+
- **DaVinci Resolve export** — same xmeml format, minimal additional work
