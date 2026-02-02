# Changelog

All notable changes to Synaxis will be documented in this file.

## [2.1.1] - 2026-01-30

### Fixed
- TSL false cuts from non-program buses (AUX, preview, clean, MiniME) — only PGM/PROGRAM buses now emit cut events
- TSL per-bus debouncing (300ms) prevents duplicate cuts during video transitions
- XML export no longer silently drops cuts for unmatched TSL source indices — uses fallback camera assignments from event data
- Export path Browse button in Settings now opens correctly (NSOpenPanel wrapped in DispatchQueue.main.async)

### Changed
- HyperDeck input picker expanded from 4 to 8 inputs with clearer "Input N" labels
- HyperDeck picker column widened for readability

## [2.1.0] - 2026-01-30

### Changed
- Renamed project from "Touchdrive to Premiere" to "Synaxis"
- Replaced asset catalog app icon with pre-built AppIcon.icns

### Added
- Multi-ProPresenter machine support

### Fixed
- HyperDeck recording feedback (polling, button state, post-command query)
- TSL false cuts on initial connection (3-second suppression window)
- TSL "Listen Port" label wrapping to two lines

## [2.0.0] - 2026-01-29

### Changed
- Replaced RossTalk protocol with TSL 5.0 for Ultrix Carbonite integration
- Replaced AppCoordinator god object with four focused @Observable ViewModels:
  ConnectionManager, AssignmentStore, SettingsManager, SessionManager
- Migrated from ObservableObject/@Published to @Observable macro (Swift 5.9+)
- Rewrote PremiereXMLGenerator using Foundation.XMLDocument for proper XML escaping
- ProPresenter client uses correct port (1025) and no authentication for HTTP API
- HyperDeck client uses correct \r\n line termination and right-to-left clip name parsing
- Target macOS 15 Sequoia (deployment target 15.0)
- NavigationSplitView sidebar with Monitor and Configuration sections
- ProPresenter configuration changed from multi-instance to single-config panel

### Added
- TSL 5.0 TCP listener (NWListener) with auto-detection of TSL 3.1 fallback
- Full bus state model tracking all ME program/preview sources
- Carbonite label parsing (source-index:bus-label:source-label format)
- HyperDeck start/stop recording controls in the app
- Dashboard view with live connection status, program source, timecode, event feed
- Multi-track timeline export: V1 program cut, V2-V4 ISOs, V5 graphics, A1-A4 audio
- Timeline markers for keyer and ProPresenter slide events
- Drop-frame timecode support for 29.97 and 59.94 fps with proper NTSC detection
- Structured logging via os.Logger with per-service categories (tsl, proPresenter, hyperDeck, session, export, ui)
- Settings pane (Cmd+Comma) with Connections, Project, Export, and Timecode tabs
- Exponential backoff reconnection for ProPresenter and HyperDeck
- Auto-export of both Premiere XML and session JSON when recording stops
- Export filename tokens: {session}, {date}, {time}, {count}
- Back-to-back session support with in-app session naming
- XML preview window with track/marker counts and copy-to-clipboard
- Connection status panel with per-service indicators
- Camera assignment with TSL index stepper and HyperDeck channel picker
- Keyer assignment with ME number and keyer number pickers
- HyperDeck timecode stamped onto TSL and ProPresenter events
- Unit test target with TSL, timecode, XML generator, HyperDeck, and event logger tests
- Keyboard shortcut Cmd+R for toggle recording

### Fixed
- 28 bugs from v1.0 audit (see PRD.md Section 11)
- Force-unwrap crashes in ProPresenter and HyperDeck clients
- Static DateFormatter in EventLogView prevents per-row allocation
- Pulse animation uses .repeatForever(autoreverses:) correctly
- Duplicate client instances eliminated by centralized ConnectionManager
- UserDefaults registers correct first-launch defaults
- ProPresenter slide fingerprinting prevents duplicate events on re-trigger
- HyperDeck clip name parsing handles spaces correctly (right-to-left tokenization)

## [1.0.0] - 2026-01-28

### Added
- Initial implementation by Seth Potter
- RossTalk client for Ross Carbonite/Ultrix
- ProPresenter client for slide monitoring
- HyperDeck client for recorder integration
- Premiere XML export (FCP XML format)
- Camera and keyer assignment configuration
- Event logging with session management
- Diagnostics view with test event generation
