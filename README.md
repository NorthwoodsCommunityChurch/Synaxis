# Synaxis

Real-time broadcast production monitor and Adobe Premiere timeline generator for multi-camera live events.

<!-- TODO: Add screenshot to docs/images/ -->

## Features

- **TSL 5.0 tally monitoring** — listens for tally data from Ross Ultrix Carbonite production switchers
- **ProPresenter 7 integration** — tracks slide transitions via HTTP REST and chunked streaming
- **HyperDeck Extreme 8K control** — start/stop recording, timecode sync via Ethernet Protocol
- **Premiere XML export** — generates multi-track FCP XML timelines with program cuts, ISO tracks, graphics, and audio
- **Live dashboard** — real-time connection status, program source, timecode, and event feed
- **Timeline visualization** — in-app timeline preview of captured production events
- **Multi-ProPresenter support** — monitor multiple ProPresenter machines simultaneously
- **Drop-frame timecode** — proper NTSC detection for 29.97 and 59.94 fps workflows
- **Back-to-back sessions** — name and manage consecutive recording sessions

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon (aarch64)

## Installation

1. Download the latest `.zip` from [Releases](https://github.com/NorthwoodsCommunityChurch/Synaxis/releases)
2. Extract the zip
3. Right-click `Synaxis.app` and select **Open** (required on first launch for ad-hoc signed apps)

## Usage

1. **Configure connections** — set the TSL listener port, ProPresenter host/port, and HyperDeck IP in Settings (Cmd+,)
2. **Assign cameras** — map TSL source indices to camera names and HyperDeck inputs
3. **Configure the Carbonite** — in Ross DashBoard, add a TSL UMD device pointing to this Mac's IP and port (default 5201)
4. **Monitor** — watch the live dashboard for connection status, program source, and event feed
5. **Record** — use Cmd+R or the HyperDeck controls to start/stop recording
6. **Export** — after recording, export the timeline as Premiere XML or review it in the timeline view

## Configuration

### Ross Carbonite / Ultrix
In DashBoard: Configuration > Devices > Add Device > Type: TSL UMD > Driver: TSL 5. Set the IP to this Mac's address and port to 5201 (or your configured port).

### ProPresenter 7
Enter the ProPresenter machine's IP and API port (default 1025). The HTTP API requires no authentication. Optional: configure Remote password for control features.

### HyperDeck Extreme 8K
Enter the HyperDeck's IP address. Default port is 9993. Assign SDI inputs (1-8) to cameras for ISO track mapping.

## Building from Source

```bash
cd "Touchdrive to Premiere"
xcodebuild -project "Touchdrive to Premiere.xcodeproj" \
  -scheme "Touchdrive to Premiere" \
  -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

The Xcode project directory is named "Touchdrive to Premiere" (the app's original name). The built product is `Synaxis.app`.

## Project Structure

```
Synaxis/
├── Touchdrive to Premiere/          # Xcode project directory
│   └── Touchdrive to Premiere/      # Swift source
│       ├── Models/                   # Data structures
│       ├── Services/                 # Network clients (TSL, ProPresenter, HyperDeck, XML)
│       ├── ViewModels/               # @Observable state management
│       ├── Views/                    # SwiftUI views
│       │   ├── Dashboard/            # Live monitoring
│       │   └── Timeline/             # Timeline visualization
│       └── Utilities/                # Timecode helpers, logging
├── Tools/                            # Python simulators for testing
├── docs/                             # Protocol specs and API references
├── Icon/                             # App icon assets
├── CREDITS.md
├── CHANGELOG.md
├── LICENSE
└── SECURITY.md
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Credits

See [CREDITS.md](CREDITS.md) for third-party references and acknowledgments.
