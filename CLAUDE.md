# Synaxis — Project Context for Claude Code

## What This App Does

Synaxis is a macOS SwiftUI app that monitors live broadcast production equipment in real time and exports Adobe Premiere-compatible XML timelines. It sits on the network during a live multi-camera event, captures every camera cut, keyer change, and ProPresenter slide transition, then generates a rough-cut timeline for post-production.

## Hardware Integrations

- **Ross Ultrix Carbonite** — production switcher, monitored via TSL 5.0 protocol (TCP listener, binary)
- **ProPresenter 7** — presentation software, monitored via HTTP REST + chunked streaming
- **Blackmagic HyperDeck Extreme 8K** — recorder, controlled via Ethernet Protocol (TCP 9993, text-based, `\r\n` terminated)
- **Canon C200 cameras** — file transfer via embedded FTP server (cameras push MP4 files over FTP)

## Architecture

MVVM pattern with `@Observable` (Swift 5.9+):

- **Models/** — Data structures (ProductionEvent, ProductionSession, BusState, assignments, configs)
- **Services/** — Network clients (TSLClient, ProPresenterClient, HyperDeckClient, FTPServer, FTPSession, EventLogger, PremiereXMLGenerator)
- **ViewModels/** — State management (ConnectionManager, AssignmentStore, SettingsManager, SessionManager)
- **Views/** — SwiftUI views organized by feature (Dashboard, Configuration, Settings, Diagnostics, etc.)
- **Utilities/** — Helpers (TimecodeHelpers, Logging)

## File Map

How features flow through the code — use this to go directly to the right files:

- **Cut detection**: TSLClient → ConnectionManager → SessionManager → ProductionEvent model
- **XML/timeline export**: SessionManager → PremiereXMLGenerator
- **HyperDeck recording control**: HyperDeckClient → ConnectionManager
- **ProPresenter slides**: ProPresenterClient → ConnectionManager → SessionManager
- **Camera/keyer assignments**: AssignmentStore → Views/CameraAssignmentView + Views/AssignmentsView
- **Timeline layout UI**: TimelineLayoutStore → Views/Timeline/
- **App settings/preferences**: SettingsManager → Views/SettingsView
- **Dashboard/live monitor**: DashboardView (uses ConnectionManager + SessionManager)
- **Diagnostics/debugging**: DiagnosticsView (reads from ConnectionManager)
- **App structure/navigation**: ContentView (sidebar) → Touchdrive_to_PremiereApp (app entry)
- **FTP file transfers**: FTPServer + FTPSession → ConnectionManager → SessionManager
- **Timecode math**: Utilities/TimecodeHelpers
- **Version/updates**: Models/Version.swift (source of truth), ViewModels/UpdateManager, Views/UpdateSettingsTab

## Build

```bash
cd "Touchdrive to Premiere"
xcodebuild -project "Touchdrive to Premiere.xcodeproj" \
  -scheme "Touchdrive to Premiere" \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

The Xcode project and directory names still reference "Touchdrive to Premiere" on disk. The built product is `Synaxis.app` (via `PRODUCT_NAME = Synaxis`).

## Important Protocols

- **TSL 5.0** — Binary TCP. App is a listener (server). The Carbonite connects TO the app. Messages: 2-byte PBC (little-endian) + version + flags + screen + index + control + text. Tally bits: 0-1 = program, 2-3 = preview.
- **HyperDeck Ethernet** — Text TCP on port 9993. `\r\n` line termination. Response codes: 200 OK, 208 transport info, 500 connection info, 508 async notification.
- **ProPresenter REST** — HTTP chunked streaming on `/v1/status/slide` for real-time slide detection. No authentication for HTTP API.

## Notes

- The TSL listener suppresses cut events for 3 seconds after a new connection to avoid false positives from the Carbonite's initial state dump.
- TSL bus filtering: program cut events are emitted for buses containing "PGM" or "PROGRAM", or ending with "bg" (Ross Carbonite background buses like ME1bg, ME2bg). All other buses (PVW, CLN, AUX, MiniME, Pst, keyer layers) are ignored to prevent false cuts.
- TSL per-bus debouncing: 300ms `ContinuousClock`-based debounce per bus prevents duplicate cuts during video transitions.
- HyperDeck transport is polled every 1 second as a fallback since async notifications (code 508) are unreliable.
- HyperDeck input assignment per camera supports inputs 1-8 (matching HyperDeck Extreme 8K's SDI input count).
- The XML generator uses fallback camera assignments for unmatched TSL source indices — no cuts are silently dropped. If a TSL source index doesn't match any configured camera, a placeholder `CameraAssignment` is created from the event data.
- NSOpenPanel in SwiftUI Settings windows requires wrapping `runModal()` in `DispatchQueue.main.async {}` to work correctly (direct calls and `beginSheetModal` both fail silently).
- The app icon is a pre-built `AppIcon.icns` file (not from the asset catalog) because Xcode's actool doesn't generate complete icns files for this project.
- Multi-ProPresenter support uses a `[UUID: ProPresenterClient]` dictionary in ConnectionManager.
- FTP server runs on configurable port (default 2121, avoids root-required port 21). Global username/password auth. Files saved to `{base path}/{YYYY-MM-DD}/`. Uses security-scoped bookmarks for sandbox write access.
- FTP sessions handle PASV/EPSV passive mode with ephemeral NWListener data channels. File I/O on background `DispatchQueue(qos: .utility)` to avoid blocking UI.
- Canon C200 is the FTP client (push-only). Configure camera with Synaxis Mac IP, port, and the global FTP credentials.
