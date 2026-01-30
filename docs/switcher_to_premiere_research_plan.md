# Ross Ultrix/Carbonite to Premiere Pro Automation App
## Research & Implementation Plan

---

## Executive Summary

This document outlines the technical specifications, research findings, and implementation plan for an application that monitors a Ross video switcher (Ultrix router and Carbonite switcher), listens to ProPresenter graphics, and automatically generates Adobe Premiere Pro projects based on live production decisions.

**Core Concept:** Monitor switcher cuts/transitions and key operations in real-time, track ProPresenter graphics assignments, then reconstruct the entire production as an editable Premiere Pro timeline with proper camera angles and graphics layers.

---

## System Architecture Overview

```
┌─────────────────┐
│  Ross Carbonite │ 
│    Switcher     │──► RossTalk (TCP 7788)
└─────────────────┘

┌─────────────────┐
│  Ross Ultrix    │
│     Router      │──► RossTalk (TCP 7788) 
└─────────────────┘
                                ┌──────────────────┐
                                │   Your App       │
                                │  (Event Logger)  │
                                └──────────────────┘
                                         │
┌─────────────────┐                     │
│  ProPresenter   │                     ▼
│   Graphics      │──► WebSocket    ┌──────────────────┐
└─────────────────┘    (Port varies) │ Premiere Project │
                                     │   Generator      │
                                     └──────────────────┘
                                              │
                                              ▼
                                     ┌──────────────────┐
                                     │ Premiere Pro XML │
                                     │  or ExtendScript │
                                     └──────────────────┘
```

---

## Research Findings

### 1. Ross RossTalk Protocol

**What It Is:**
RossTalk is a plain-text TCP protocol for controlling Ross equipment (switchers, routers, graphics engines).

**Key Details:**

#### Connection Information
- **Protocol:** TCP/IP
- **Port:** 7788 (default, can be incremented for multiple connections)
- **Format:** Plain ASCII text commands
- **Termination:** Each command must end with CR/LF (Carriage Return/Line Feed)
- **Default IP:** 192.168.0.123 (for Carbonite switchers)

#### Carbonite Switcher Commands (Relevant for Monitoring)

For your app, you'll primarily be **receiving** status information rather than sending commands. However, understanding the command structure helps parse responses:

**Key Commands to Monitor:**

1. **MEAUTO** - ME (Mix/Effects) auto transition
   - Format: `MEAUTO ME:<me_number>`
   - Example: `MEAUTO ME:1` (triggers auto transition on ME 1)

2. **MECUT** - ME cut transition
   - Format: `MECUT ME:<me_number>`
   - Example: `MECUT ME:1`

3. **KEYAUTO** - Keyer auto transition
   - Format: `KEYAUTO ME:<me>:<keyer>`
   - Example: `KEYAUTO ME:1:2` (auto transitions key 2 on ME 1)

4. **KEYCUT** - Keyer cut transition
   - Format: `KEYCUT ME:<me>:<keyer>`
   - Example: `KEYCUT ME:1:1`

5. **SELECT** - Source selection on buses
   - Format: `SELECT <destination>:<source>`
   - Destinations include:
     - `PST:<me>` - Preset bus
     - `PGM:<me>` - Program bus
     - `KEY:<me>:<keyer>` - Key bus
     - `AUX:<aux_number>` - Aux bus
   - Sources format: `IN:<input_number>`
   - Example: `SELECT PST:1:IN:3` (selects input 3 on ME 1 preset)

**ME (Mix Effects) Numbering:**
- Carbonite Black: ME 1, ME 2, ME 3 (highest is program)
- Carbonite Ultra: ME 2, ME 1, ME P/P (P/P is program)

#### Ultrix Router Commands

1. **XPT** (Crosspoint) - Routes input to output
   - Format: `XPT <level> <destination> <source>`
   - Example: `XPT 0 5 12` (routes source 12 to destination 5 on level 0)

2. **SALVO** - Trigger saved routing configuration
   - Format: `SALVO <salvo_number>`
   - Example: `SALVO 23`

**Monitoring Strategy:**
To monitor the switcher, you'll need to:
1. Connect as a client to the RossTalk port
2. Parse incoming status messages
3. Log state changes (which input is on program, which keys are active, etc.)

**Important Note:** RossTalk protocol documentation suggests that switchers can send status updates, but you may need to poll for status or enable status reporting depending on your specific hardware version.

---

### 2. ProPresenter API

**What It Is:**
ProPresenter exposes multiple APIs for control and monitoring of presentation software used for lyrics, graphics, and lower thirds in live production.

**Available API Methods:**

#### A. Legacy WebSocket Protocol (Pro 6 & 7)

**Connection Details:**
- **Protocol:** WebSocket
- **Endpoint:** `ws://<ip>:<port>/<channel>`
- **Channels:**
  - `/remote` - Control channel
  - `/stagedisplay` - Stage display monitoring
- **Default Port:** Usually 5000-6000 range (configurable in ProPresenter settings)
- **Authentication:** Required immediately after connection

**Pro7 Specific Requirements:**
- Protocol version must be 701 or higher (for Pro 7.4.2+)
- Headers must be in CamelCase (non-standard HTTP spec)
- Required headers:
  ```
  Upgrade: websocket
  Connection: Upgrade
  Sec-WebSocket-Key: <key>
  Sec-WebSocket-Version: 13
  ```

**Authentication Message:**
```json
{
  "action": "authenticate",
  "protocol": "701",
  "password": "<password>"
}
```

**Response:**
```json
{
  "controller": 1,
  "authenticated": 1,
  "error": "",
  "majorVersion": 7,
  "minorVersion": 6,
  "action": "authenticate"
}
```

**Key Actions to Monitor:**

1. **presentationCurrent** - Get currently active presentation
   ```json
   {"action": "presentationCurrent"}
   ```

2. **presentationTriggerIndex** - Notification when slide changes
   ```json
   {
     "action": "presentationTriggerIndex",
     "slideIndex": 0,
     "presentationPath": "/Path/To/Presentation.pro"
   }
   ```

3. **presentationSlideIndex** - Current slide information
   - Includes slide text, image, notes
   - Updates automatically when subscribed

#### B. Modern HTTP REST API (Pro 7.9+)

**Connection Details:**
- **Protocol:** HTTP/HTTPS
- **Base URL:** `http://<ip>:<port>/v1/`
- **Port:** Configurable in ProPresenter Network settings
- **Documentation:** Available in ProPresenter → Preferences → Network → "API Documentation" button

**Key Endpoints (likely available):**
- `/v1/presentation/active` - Get active presentation info
- `/v1/presentation/slide_index` - Current slide
- `/v1/status/updates` - Subscribe to status updates (streaming)
- `/v1/stage/message` - Stage display messages

#### C. TCP/IP API (Alternative)

**Connection Details:**
- Single TCP socket connection
- JSON requests terminated by CRLF
- Request format:
  ```json
  {
    "url": "v1/presentation/active",
    "method": "GET",
    "chunked": false
  }
  ```

**For Your Use Case:**
You need to monitor:
1. When presentations are triggered (for graphics on/off)
2. Which slide is active (for graphic identification)
3. Presentation metadata (to map to keyer assignments)

**Implementation Strategy:**
- Connect via WebSocket to `/remote` channel
- Subscribe to slide change notifications
- Track presentation state changes
- Map presentations to specific keyers (user-configurable)

---

### 3. Adobe Premiere Pro Integration

**Challenge:** Premiere Pro's project file format (.prproj) is proprietary and binary, not directly editable.

**Available Approaches:**

#### A. Final Cut Pro XML Format (Recommended)

**What It Is:**
An interchange format that Premiere Pro can import/export for project data.

**Capabilities:**
- Timeline structure (sequences)
- Clip references with in/out points
- Track layout (video/audio)
- Basic transitions (cuts, dissolves, wipes)
- Motion effects (scaling, position, opacity)
- Speed changes
- Basic audio levels and keyframes

**Limitations:**
- Proprietary effects don't transfer perfectly
- Complex color grading doesn't transfer
- Third-party plugins don't transfer
- Nested sequences have limited support

**XML Structure (Simplified):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xmeml>
<xmeml version="5">
  <project>
    <name>MyProject</name>
    <children>
      <bin>
        <name>Media</name>
        <children>
          <clip id="clip-1">
            <name>Camera1.mp4</name>
            <file>
              <pathurl>file://localhost/path/to/Camera1.mp4</pathurl>
            </file>
          </clip>
        </children>
      </bin>
      <sequence>
        <name>MainSequence</name>
        <media>
          <video>
            <track>
              <clipitem id="clipitem-1">
                <masterclipid>clip-1</masterclipid>
                <start>0</start>
                <end>300</end>
                <in>0</in>
                <out>300</out>
              </clipitem>
            </track>
          </video>
        </media>
      </sequence>
    </children>
  </project>
</xmeml>
```

**Import Process:**
1. Generate XML file with project structure
2. In Premiere: File → Import → select XML
3. Premiere creates bins, sequences, and links media

**Best Practices:**
- Use absolute file paths for media references
- Organize clips in bins matching your camera assignments
- Create separate video tracks for different sources
- Use track naming to identify camera/graphics layers
- Keep transitions simple (cuts work universally)

#### B. ExtendScript API (Advanced)

**What It Is:**
JavaScript-based scripting environment for Premiere Pro automation.

**Access:** Via CEP (Common Extensibility Platform) panels or standalone scripts

**Capabilities:**
- Create/modify projects programmatically
- Import media files
- Create sequences
- Add clips to timeline with specific in/out points
- Set clip properties (position, scale, effects)
- No transcription API available

**Key Objects:**
```javascript
// Access application
var app = app;

// Get or create project
var project = app.project;

// Import media
var file = new File("/path/to/media.mp4");
project.importFiles([file.fsName]);

// Get imported item
var projectItem = project.rootItem.children[0];

// Create sequence
var sequence = project.createNewSequence("MainSequence", "sequence-preset");

// Add clip to timeline
var videoTrack = sequence.videoTracks[0];
videoTrack.insertClip(projectItem, 0); // Insert at timecode 0
```

**Limitations:**
- Requires Premiere Pro to be running
- More complex to deploy
- User needs to have ExtendScript enabled
- Scripts must be packaged as CEP extensions for distribution

#### C. UXP API (Modern, Premiere v25.6+)

**What It Is:**
Unified Extensibility Platform - the next generation of Premiere Pro APIs.

**Advantages:**
- Modern JavaScript (ES6+)
- Better performance
- Native access to Premiere DOM
- Can create full UI panels

**Status:** Newer technology, requires recent Premiere Pro versions

**For Your Use Case:**
XML is the recommended approach because:
1. Works without Premiere running during generation
2. Can be generated by any programming language
3. User just imports the file - simple workflow
4. No installation/plugin required
5. Cross-platform compatible

---

## Application Requirements

### Core Functionality

1. **Real-Time Monitoring**
   - Connect to Ross Carbonite switcher (RossTalk TCP 7788)
   - Connect to Ross Ultrix router (RossTalk TCP 7788) 
   - Connect to ProPresenter (WebSocket or HTTP API)
   - Log all events with precise timestamps

2. **Event Tracking**
   - Switcher cuts (Program bus changes)
   - Switcher transitions (Auto transitions with duration)
   - Keyer on/off state changes
   - ProPresenter slide triggers
   - Duration of each "shot"

3. **Camera Assignment**
   - User interface to map video files to switcher inputs
   - Example: Input 1 → Camera1_Angle.mp4
   - Example: Input 2 → Camera2_Closeup.mp4
   - Support for multiple file formats (MP4, MOV, MXF, etc.)

4. **Graphics/Keyer Assignment**
   - Map ProPresenter presentations to keyer numbers
   - Example: Keyer 1 → Lower Thirds presentation
   - Example: Keyer 2 → Song Lyrics presentation
   - Extract graphics/slides as image sequence or video

5. **Premiere Project Generation**
   - Generate Final Cut Pro XML file
   - Create timeline with video tracks for each camera
   - Add graphics layers corresponding to keyer activity
   - Sync all elements to logged timestamps
   - Include proper media references

6. **User Interface**
   - Connection status indicators
   - Live event log display
   - Camera/file assignment panel
   - ProPresenter/keyer mapping panel
   - Project generation controls
   - Preview of timeline structure

---

## Technical Implementation Plan

### Phase 1: Core Monitoring (Week 1-2)

**Tasks:**

1. **RossTalk Client Implementation**
   - Create TCP client connecting to port 7788
   - Implement command parser for RossTalk messages
   - Handle CR/LF terminated messages
   - Parse SELECT, MECUT, MEAUTO, KEYCUT, KEYAUTO commands
   - Log all switcher state changes with timestamps

2. **Ultrix Router Monitoring**
   - Connect to Ultrix RossTalk interface (port 7788)
   - Parse XPT and SALVO commands
   - Track routing changes

3. **Event Logger**
   - Create time-stamped event queue
   - Event types:
     - `CUT`: { timestamp, source_input, me_number }
     - `TRANSITION`: { timestamp, type, duration, source_input, me_number }
     - `KEY_ON`: { timestamp, keyer_number, me_number }
     - `KEY_OFF`: { timestamp, keyer_number, me_number }
     - `GRAPHIC_CHANGE`: { timestamp, presentation, slide_index }
   - Serialize events to JSON for persistence

**Deliverables:**
- Working RossTalk client library
- Event logging system
- Test suite with simulated switcher data

---

### Phase 2: ProPresenter Integration (Week 2-3)

**Tasks:**

1. **WebSocket Client**
   - Implement WebSocket connection to ProPresenter
   - Handle authentication handshake
   - Subscribe to presentation and slide change events
   - Parse JSON responses

2. **Presentation State Tracking**
   - Track active presentation
   - Monitor slide index changes
   - Extract slide metadata (text, images)
   - Map presentations to keyer assignments

3. **Graphics Extraction**
   - Option A: Capture slide images via ProPresenter API
   - Option B: Export presentation slides as image sequence
   - Option C: Reference ProPresenter output as video source
   - Store graphics with timestamp metadata

**Deliverables:**
- ProPresenter monitoring client
- Graphics extraction tool
- Keyer-to-presentation mapping configuration

---

### Phase 3: Media Management (Week 3-4)

**Tasks:**

1. **Camera Assignment System**
   - UI for mapping switcher inputs to video files
   - File browser/selector
   - Validation of file existence and format
   - Support for common video formats
   - Save/load assignment configurations

2. **Timecode Synchronization**
   - Determine production start timecode
   - Convert event timestamps to timeline positions
   - Handle frame rate considerations
   - Support for multiple frame rate workflows (23.98, 24, 25, 29.97, 30, 60)

3. **Media Path Management**
   - Absolute vs relative path handling
   - Cross-platform path compatibility (Windows/Mac)
   - Media relinking strategies

**Deliverables:**
- Camera assignment UI
- Timecode calculation engine
- Media path manager

---

### Phase 4: XML Generator (Week 4-5)

**Tasks:**

1. **XML Structure Builder**
   - Implement Final Cut Pro XML 5.0 format
   - Create project header
   - Define sequence settings
   - Build bin structure

2. **Timeline Construction**
   - Create video tracks for each camera source
   - Add clipitems based on logged cuts
   - Calculate accurate in/out points
   - Handle transition types (cuts vs dissolves)

3. **Graphics Layer Integration**
   - Create additional video tracks for graphics
   - Place graphic clips based on keyer events
   - Handle opacity and compositing
   - Support for alpha channel media

4. **XML Output**
   - Generate well-formed XML
   - Include all media references
   - Add sequence markers for reference
   - Validate XML structure

**Example XML Generation Logic:**
```python
# Pseudocode
timeline_start = first_event.timestamp

for event in event_log:
    if event.type == "CUT":
        # Add new clip to timeline
        clip_start = event.timestamp - timeline_start
        clip_duration = next_event.timestamp - event.timestamp
        source_file = camera_assignments[event.source_input]
        
        add_clip_to_track(
            track=get_camera_track(event.source_input),
            file=source_file,
            timeline_position=clip_start,
            duration=clip_duration
        )
    
    elif event.type == "KEY_ON":
        # Add graphics clip
        presentation = keyer_assignments[event.keyer_number]
        graphic_file = get_graphic_for_presentation(presentation)
        
        add_clip_to_track(
            track=get_graphics_track(event.keyer_number),
            file=graphic_file,
            timeline_position=event.timestamp - timeline_start,
            duration=calculate_key_duration(event)
        )
```

**Deliverables:**
- XML generator module
- Template XML files for different scenarios
- XML validation tool

---

### Phase 5: User Interface (Week 5-6)

**Tasks:**

1. **Main Application Window**
   - Connection configuration panel
   - Status indicators (connected/disconnected)
   - Event log viewer (real-time display)

2. **Configuration Panels**
   - Camera assignment interface
   - Keyer/ProPresenter mapping interface
   - Project settings (frame rate, resolution)
   - Output preferences

3. **Project Generation Workflow**
   - Start/stop recording buttons
   - Event log review/editing
   - Generate XML button
   - Export location selector
   - Success/error notifications

4. **Additional Features**
   - Save/load configuration profiles
   - Export event log as CSV/JSON
   - Import existing event logs
   - Batch processing capability

**Technology Recommendations:**
- **Desktop App:** Electron (cross-platform) or Python with Qt/Tkinter
- **Web App:** React/Vue.js with Node.js backend
- **Mobile Monitoring:** React Native (optional)

**Deliverables:**
- Complete GUI application
- User documentation
- Configuration file formats

---

### Phase 6: Testing & Refinement (Week 6-7)

**Tasks:**

1. **Integration Testing**
   - Test with actual Ross equipment
   - Verify ProPresenter connectivity
   - Validate XML import in Premiere Pro
   - Test with various switcher configurations

2. **Edge Case Handling**
   - Disconnection/reconnection scenarios
   - Invalid data handling
   - Missing media files
   - Corrupt event logs

3. **Performance Optimization**
   - Event processing efficiency
   - Memory management for long recordings
   - XML generation speed

4. **Documentation**
   - Installation guide
   - User manual
   - Troubleshooting guide
   - API documentation

**Deliverables:**
- Test suite
- Bug fixes
- Performance improvements
- Complete documentation

---

## Data Models

### Event Log Structure
```json
{
  "production": {
    "name": "Sunday Service - 2025-01-28",
    "start_time": "2025-01-28T10:00:00.000Z",
    "frame_rate": 29.97,
    "timecode_start": "01:00:00:00"
  },
  "camera_assignments": {
    "IN:1": {
      "name": "Camera 1 - Wide",
      "file_path": "/media/cam1_wide.mp4"
    },
    "IN:2": {
      "name": "Camera 2 - Close",
      "file_path": "/media/cam2_close.mp4"
    },
    "IN:3": {
      "name": "Camera 3 - Stage Left",
      "file_path": "/media/cam3_left.mp4"
    }
  },
  "keyer_assignments": {
    "1": {
      "name": "Lower Thirds",
      "propresenter_presentation": "LowerThirds.pro7",
      "graphics_folder": "/graphics/lower_thirds/"
    },
    "2": {
      "name": "Song Lyrics",
      "propresenter_presentation": "SongLyrics.pro7",
      "graphics_folder": "/graphics/lyrics/"
    }
  },
  "events": [
    {
      "timestamp": "2025-01-28T10:00:00.000Z",
      "type": "CUT",
      "me": 1,
      "source": "IN:1",
      "destination": "PGM:1"
    },
    {
      "timestamp": "2025-01-28T10:00:15.500Z",
      "type": "KEY_ON",
      "me": 1,
      "keyer": 1
    },
    {
      "timestamp": "2025-01-28T10:00:18.000Z",
      "type": "GRAPHIC_CHANGE",
      "presentation": "LowerThirds.pro7",
      "slide_index": 5,
      "slide_text": "Pastor John Smith"
    },
    {
      "timestamp": "2025-01-28T10:00:30.250Z",
      "type": "CUT",
      "me": 1,
      "source": "IN:2",
      "destination": "PGM:1"
    },
    {
      "timestamp": "2025-01-28T10:00:45.000Z",
      "type": "KEY_OFF",
      "me": 1,
      "keyer": 1
    }
  ]
}
```

---

## Technical Stack Recommendations

### Backend/Core Engine
**Recommended:** Python 3.9+
- **Libraries:**
  - `asyncio` - Async TCP/WebSocket handling
  - `websockets` - ProPresenter WebSocket client
  - `xml.etree.ElementTree` - XML generation
  - `json` - Event log serialization
  - `pathlib` - Cross-platform file path handling
  - `datetime` / `timecode` - Timestamp management

**Alternative:** Node.js
- Good for WebSocket handling
- Easy XML generation with libraries like `xmlbuilder2`
- Large ecosystem

### Frontend/UI
**Option 1: Electron** (Recommended)
- Cross-platform desktop app
- Web technologies (HTML/CSS/JavaScript)
- Easy packaging and distribution
- Libraries: React, Vue, or vanilla JS

**Option 2: Python Qt (PyQt5/PySide6)**
- Native desktop application
- Good performance
- Mature UI framework
- Steeper learning curve

**Option 3: Web Application**
- Server-client architecture
- Access from any device
- Requires hosting infrastructure
- Real-time updates via WebSockets

### Media Handling
- **FFmpeg** - Video format detection, potential graphics extraction
- **Pillow/PIL** - Image processing (for graphics)
- **MediaInfo** - Get media file metadata

---

## Workflow Example

### Typical User Workflow

1. **Pre-Production Setup**
   - Launch application
   - Configure Ross Carbonite IP and port
   - Configure Ross Ultrix IP and port
   - Configure ProPresenter IP and port
   - Test connections (all show green indicators)

2. **Camera Assignment**
   - Open "Camera Assignment" panel
   - For each camera input:
     - Select switcher input number (e.g., IN:1)
     - Browse to video file (e.g., Camera1_Wide.mp4)
     - Assign friendly name (e.g., "Wide Shot")
   - Save configuration profile

3. **Graphics/Keyer Mapping**
   - Open "Keyer Assignment" panel
   - For each keyer:
     - Select keyer number (e.g., Keyer 1)
     - Choose ProPresenter presentation (dropdown or browse)
     - Specify graphics output folder
     - Assign friendly name (e.g., "Lower Thirds")
   - Save configuration

4. **Live Production Recording**
   - Click "Start Recording" button
   - Application monitors all connections in real-time
   - Event log displays each action:
     - "10:00:00.000 - CUT to Camera 1"
     - "10:00:15.500 - Keyer 1 ON (Lower Thirds)"
     - "10:00:18.000 - Lower Third: Pastor John Smith"
     - "10:00:30.250 - CUT to Camera 2"
   - Operator can add manual markers/notes if needed

5. **Post-Production**
   - Click "Stop Recording" button
   - Review event log
   - Make adjustments if needed:
     - Remove unwanted events
     - Adjust timing
     - Add additional notes
   - Click "Generate Premiere Project"
   - Select output location
   - Application generates XML file

6. **Import to Premiere**
   - Open Adobe Premiere Pro
   - File → Import
   - Select generated XML file
   - Premiere creates:
     - Bins organized by camera
     - Main sequence with all cuts
     - Separate tracks for each camera source
     - Graphics layers on upper tracks
   - Media files are automatically linked (if paths are correct)
   - User can now refine edit, add effects, color grade, etc.

---

## Challenges & Solutions

### Challenge 1: Switcher Status Monitoring
**Problem:** RossTalk may not automatically broadcast all state changes.

**Solutions:**
- Implement periodic polling for current state
- Request status after any detected change
- Maintain internal state machine
- Use switcher's "tally" system if available

### Challenge 2: Timecode Synchronization
**Problem:** Switcher, ProPresenter, and camera recordings may not be perfectly synchronized.

**Solutions:**
- Use NTP time synchronization on all systems
- Record slate/marker at production start
- Implement offset adjustment in UI
- Support for audio waveform sync (future enhancement)

### Challenge 3: Graphics as Video
**Problem:** ProPresenter graphics aren't saved as video files by default.

**Solutions:**
- Option A: Capture ProPresenter output as video during production
- Option B: Export slides as image sequences, generate video clips
- Option C: Use "placeholder" clips in timeline, user replaces later
- Option D: Direct ProPresenter output recording to file

### Challenge 4: XML Compatibility
**Problem:** Premiere's XML import may have limitations or quirks.

**Solutions:**
- Test with multiple Premiere Pro versions
- Keep XML structure simple (avoid advanced features)
- Provide "flavors" of XML for different NLEs (Premiere, Resolve, etc.)
- Document any manual post-import steps needed

### Challenge 5: Large Event Logs
**Problem:** Long productions generate massive event logs, slow processing.

**Solutions:**
- Implement event log chunking
- Provide filtering options (e.g., ignore preset changes)
- Optimize XML generation algorithm
- Support background processing/progress bars

### Challenge 6: Network Reliability
**Problem:** Network disconnections during production.

**Solutions:**
- Implement automatic reconnection
- Buffer events locally during disconnection
- Warn user if connection lost
- Allow manual re-sync after reconnection

---

## Future Enhancements

### Phase 2 Features
1. **Multi-Switcher Support**
   - Monitor multiple switchers simultaneously
   - Combine outputs in single timeline

2. **Audio Integration**
   - Monitor audio mixer (if supported)
   - Add audio tracks to timeline
   - Sync audio clips

3. **Advanced Graphics**
   - Real-time ProPresenter output capture
   - Alpha channel support
   - Animated transitions

4. **AI-Assisted Editing**
   - Automatic B-roll insertion suggestions
   - Smart transition recommendations
   - Content-aware clip trimming

5. **Cloud Integration**
   - Save configurations to cloud
   - Share event logs across team
   - Remote monitoring capability

6. **Presets & Templates**
   - Save common configurations
   - Quick-start templates for different production types
   - Import/export configuration profiles

7. **Analytics & Reports**
   - Production statistics
   - Camera usage breakdown
   - Graphics frequency analysis

8. **Alternative NLE Support**
   - DaVinci Resolve XML export
   - Avid Media Composer AAF export
   - Final Cut Pro FCPXML export

---

## Development Timeline

### Week 1-2: Core Monitoring
- RossTalk client implementation
- Event logging system
- Basic testing

### Week 2-3: ProPresenter Integration
- WebSocket/API client
- Graphics extraction
- Keyer mapping

### Week 3-4: Media Management
- Camera assignment system
- Timecode handling
- Path management

### Week 4-5: XML Generator
- XML structure implementation
- Timeline construction logic
- Validation

### Week 5-6: User Interface
- Main application GUI
- Configuration panels
- User workflow

### Week 6-7: Testing & Documentation
- Integration testing
- Bug fixing
- User documentation

**Total Estimated Time:** 7 weeks (for MVP)

---

## Required Information from User

To finalize the implementation, you'll need to provide:

1. **Equipment Details**
   - Exact Ross Carbonite model (Black, Ultra, etc.)
   - Ross Ultrix model and firmware version
   - Number of MEs (Mix Effects buses)
   - Number of keyers available
   - Network configuration (IP addresses, VLANs)

2. **ProPresenter Setup**
   - ProPresenter version (6 or 7, specific minor version)
   - Network control enabled? (port number)
   - Remote control password (if set)
   - Graphics output method (SDI, NDI, network stream)

3. **Production Workflow**
   - Typical camera count (how many angles)
   - Keyer usage patterns (lower thirds, full screen, etc.)
   - Media file formats (codecs, resolutions)
   - Frame rates used
   - Timecode source (free run, jam sync, etc.)

4. **Post-Production Environment**
   - Premiere Pro version
   - Operating system (Windows/Mac)
   - Storage setup (local, network, SAN)
   - Preferred media formats for edit

5. **Preferences**
   - Desktop app vs web app
   - Platform priority (Windows, Mac, Linux)
   - Deployment method (single machine vs multi-user)

---

## Conclusion

This application will streamline your video production workflow by automatically capturing all switching decisions and reconstructing them as an editable Premiere Pro timeline. By monitoring the Ross switcher and ProPresenter in real-time and intelligently mapping video sources and graphics, you'll eliminate hours of manual edit recreation work.

The recommended approach using RossTalk monitoring, ProPresenter WebSocket API, and Final Cut Pro XML generation provides the most robust and maintainable solution with the broadest compatibility.

Next steps:
1. Validate technical approach with your specific equipment
2. Choose development platform and UI framework
3. Begin Phase 1 implementation (Core Monitoring)
4. Iterative testing with your production environment

---

## Appendix: Quick Reference

### RossTalk Commands Summary
```
MECUT ME:1              - Cut on ME 1
MEAUTO ME:1             - Auto transition on ME 1
KEYCUT ME:1:2           - Cut key 2 on ME 1
KEYAUTO ME:1:2          - Auto key 2 on ME 1
SELECT PGM:1:IN:3       - Select input 3 to program on ME 1
SELECT PST:1:IN:5       - Select input 5 to preset on ME 1
```

### ProPresenter WebSocket Actions
```
authenticate            - Initial auth
presentationCurrent     - Get active presentation
presentationTriggerIndex - Slide change notification
libraryRequest          - Get presentation library
```

### Premiere XML Key Elements
```xml
<xmeml>              - Root element
  <project>          - Project container
    <sequence>       - Timeline sequence
      <media>
        <video>      - Video tracks
          <track>    - Individual track
            <clipitem> - Clip on timeline
```

### Port Reference
- RossTalk: TCP 7788
- ProPresenter WebSocket: Varies (5000-6000 range, check settings)
- ProPresenter HTTP API: Varies (check settings)

---

**Document Version:** 1.0  
**Date:** January 28, 2026  
**Author:** Claude (Anthropic)
