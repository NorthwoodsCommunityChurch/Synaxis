# Security

## Deployment Environment

Synaxis is designed for use on **trusted local production networks** — the same LAN as your Ross Carbonite switcher, ProPresenter machines, and HyperDeck recorders. It is not intended for internet-facing deployment.

## Network Ports

| Service | Direction | Port | Protocol |
|---------|-----------|------|----------|
| TSL 5.0 listener | Inbound | 5201 (configurable) | TCP |
| ProPresenter API | Outbound | User-configured | HTTP |
| ProPresenter Remote | Outbound | User-configured | TCP |
| HyperDeck Ethernet | Outbound | 9993 (configurable) | TCP |

### TSL Listener (Inbound)

The app runs a TCP server (via `NWListener`) that accepts connections from the production switcher. The Carbonite connects TO the app to deliver tally data. This listener accepts connections from any source on the configured port.

**Recommendation:** Ensure the production network is isolated from untrusted networks. The TSL protocol has no authentication — any device that can reach the listener port can send tally data.

### ProPresenter (Outbound)

The app connects to ProPresenter's HTTP API for slide monitoring. The HTTP API (port 1025 by default) requires no authentication. The optional Remote control feature uses a separate port with password authentication.

### HyperDeck (Outbound)

The app connects to the HyperDeck Ethernet Protocol on port 9993. This protocol has no authentication.

## Authentication Model

- **TSL 5.0:** No authentication (protocol limitation)
- **ProPresenter HTTP API:** No authentication required
- **ProPresenter Remote:** Optional password, stored in UserDefaults (macOS user preferences)
- **HyperDeck:** No authentication (protocol limitation)

No external cloud services, OAuth, or API keys are used.

## Data Handling

- **Production events** are stored in memory during the session
- **Exported XML files** and **session JSON** are written to user-selected directories
- **App preferences** (ports, camera assignments) are stored in macOS UserDefaults
- No data is transmitted to external services or the internet

## App Sandbox

The app runs in the macOS App Sandbox with the following entitlements:

- `network.client` — connect to ProPresenter and HyperDeck
- `network.server` — accept TSL connections from the switcher
- `files.user-selected.read-write` — save exported XML/JSON to user-chosen locations

## Vulnerability Reporting

If you discover a security issue, please open an issue at:
https://github.com/NorthwoodsCommunityChurch/Synaxis/issues
