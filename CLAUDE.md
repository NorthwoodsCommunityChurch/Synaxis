# Synaxis — Project Context for Claude Code

## What This App Does

Synaxis is a macOS SwiftUI app that monitors live broadcast production equipment in real time and exports Adobe Premiere-compatible XML timelines. It sits on the network during a live multi-camera event, captures every camera cut, keyer change, and ProPresenter slide transition, then generates a rough-cut timeline for post-production.

## Hardware Integrations

- **Ross Ultrix Carbonite** — production switcher, monitored via TSL 5.0 protocol (TCP listener, binary)
- **ProPresenter 7** — presentation software, monitored via HTTP REST + chunked streaming
- **Blackmagic HyperDeck Extreme 8K** — recorder, controlled via Ethernet Protocol (TCP 9993, text-based, `\r\n` terminated)

## Architecture

MVVM pattern with `@Observable` (Swift 5.9+):

- **Models/** — Data structures (ProductionEvent, ProductionSession, BusState, assignments, configs)
- **Services/** — Network clients (TSLClient, ProPresenterClient, HyperDeckClient, EventLogger, PremiereXMLGenerator)
- **ViewModels/** — State management (ConnectionManager, AssignmentStore, SettingsManager, SessionManager)
- **Views/** — SwiftUI views organized by feature (Dashboard, Configuration, Settings, Diagnostics, etc.)
- **Utilities/** — Helpers (TimecodeHelpers, Logging)

## Key Files

- `ContentView.swift` — NavigationSplitView with sidebar sections (Monitor + Configuration)
- `Touchdrive_to_PremiereApp.swift` — `@main` App struct (struct name: `SynaxisApp`)
- `ConnectionManager.swift` — Manages all device connections, routes events to SessionManager
- `PremiereXMLGenerator.swift` — Generates xmeml v4 XML for Adobe Premiere import

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
- HyperDeck transport is polled every 1 second as a fallback since async notifications (code 508) are unreliable.
- The app icon is a pre-built `AppIcon.icns` file (not from the asset catalog) because Xcode's actool doesn't generate complete icns files for this project.
- Multi-ProPresenter support uses a `[UUID: ProPresenterClient]` dictionary in ConnectionManager.
