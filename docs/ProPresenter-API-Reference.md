# ProPresenter 7 — API Integration Reference

## Current Version
- Latest stable: **21.0.1** (Build 352321797, November 26, 2025)
- Latest beta: **21.2** (Build 352452641, January 27, 2026)
- Version numbering changed: 7.0 → 7.16.3 → 17 → 18 → 19 → 20 → 21 (same product lineage)
- REST API introduced in version **7.9**
- Platforms: macOS (Apple Silicon + Intel), Windows

## Network Configuration
- **Default port:** 1025 (auto-assigned, configurable in Settings > Network)
- HTTP API, WebSocket, and TCP/IP API all share the same port
- Enable in: ProPresenter Settings > Network > Enable Network
- No authentication required for HTTP API (accessible to all devices on network)

## API Documentation
- Official interactive docs: https://openapi.propresenter.com/
- Local docs: ProPresenter Settings > Network > "API Documentation" button
- Official OpenAPI spec: https://openapi.propresenter.com/swagger.json
- Community spec: https://github.com/jeffmikels/ProPresenter-API

## Real-Time Monitoring (Chunked HTTP)

ProPresenter uses **chunked HTTP responses** for real-time updates. The connection stays open and ProPresenter sends a new JSON chunk each time data changes.

### Key Streaming Endpoints
| Endpoint | Monitors |
|----------|----------|
| `/v1/status/slide` | Current/next slide text, image UUIDs, presentation info |
| `/v1/status/screens` | Screen configuration changes |
| `/v1/status/layers` | Layer state changes |
| `/v1/status/stage_screens` | Stage screen changes |
| `/v1/status/audience_screens` | Audience screen changes |
| `/v1/timers/current` | Timer values (every second) |
| `/v1/timer/system_time` | Unix timestamp (every second) |
| `/v1/playlist/current` | Active playlist changes |
| `/v1/playlist/active` | Active playlist item changes |
| `/v1/look/current` | Current look changes |
| `/v1/capture/status` | Capture state changes |
| `/v1/messages` | Message state changes |

### Aggregator Endpoint
`/v1/status/updates` — consolidates multiple streaming endpoints into one connection (avoids browser 5-6 connection limit).

## Complete REST API Endpoints

All paths prefixed with `/v1/`. The `{id}` parameter accepts UUID, name, or numeric index.

### Version
| Method | Path | Description |
|--------|------|-------------|
| GET | `/version` | System info: name, platform, os_version, host_description, api_version |

### Presentation
| Method | Path | Description |
|--------|------|-------------|
| GET | `/presentation/active` | Currently active presentation |
| PUT | `/presentation/active/focus` | Focus active presentation |
| POST | `/presentation/active/trigger` | Trigger slide index in active presentation |
| POST | `/presentation/active/next` | Next slide |
| POST | `/presentation/active/previous` | Previous slide |
| GET | `/presentation/{uuid}` | Presentation details (groups, slides, has_timeline) |
| GET | `/presentation/{uuid}/slide/{index}` | Specific slide details |
| GET | `/presentation/slide_index` | Current slide index |
| GET | `/presentation/{uuid}/thumbnail/{index}` | Slide thumbnail |

### Announcement
| Method | Path | Description |
|--------|------|-------------|
| GET | `/announcement/active` | Active announcement |
| PUT | `/announcement/active/focus` | Focus active announcement |
| POST | `/announcement/active/trigger` | Trigger announcement slide |
| POST | `/announcement/active/next` | Next announcement slide |
| POST | `/announcement/active/previous` | Previous announcement slide |

### Playlist
| Method | Path | Description |
|--------|------|-------------|
| GET | `/playlists` | All playlists |
| POST | `/playlists` | Create playlist |
| GET | `/playlist/current` | Active playlist (streaming) |
| GET | `/playlist/active` | Active playlist info (streaming) |
| PUT | `/playlist/{id}/focus` | Focus playlist |
| POST | `/playlist/{id}/trigger` | Trigger playlist item |
| GET | `/playlist/{id}` | Playlist items (pagination via `start`) |

### Library
| Method | Path | Description |
|--------|------|-------------|
| GET | `/libraries` | All libraries |
| GET | `/library/{id}` | Library items (streaming) |

### Status (Streaming)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/status/slide` | Current/next slide (streaming) |
| GET | `/status/screens` | Screens (streaming) |
| GET | `/status/layers` | Layers (streaming) |
| GET | `/status/stage_screens` | Stage screens (streaming) |
| GET | `/status/audience_screens` | Audience screens (streaming) |
| GET | `/status/updates` | Aggregated streaming |

### Transport (Media Playback)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/transport/layer/current` | Transport state for layer |
| POST | `/transport/layer/play` | Play media on layer |
| POST | `/transport/layer/pause` | Pause media on layer |
| GET | `/transport/layer/time` | Current playback time |
| PUT | `/transport/layer/time` | Set/scrub playback time |

### Clear
| Method | Path | Description |
|--------|------|-------------|
| GET | `/clear/layer/{layer}` | Clear layer: `audio`, `props`, `messages`, `announcements`, `slide`, `media`, `video_input` |
| GET | `/clear/groups` | List clear groups |
| POST | `/clear/groups` | Create clear group |
| GET | `/clear/group/{id}/trigger` | Execute clear group |

### Timers
| Method | Path | Description |
|--------|------|-------------|
| GET | `/timers` | All timers |
| POST | `/timers` | Create timer |
| GET | `/timers/current` | Timer values (streaming) |
| GET | `/timer/{id}` | Timer details |
| PUT | `/timer/{id}` | Update timer |
| DELETE | `/timer/{id}` | Delete timer |
| POST | `/timer/{id}/operation` | Start/stop/reset |
| GET | `/timer/system_time` | System time (streaming) |

### Messages (Overlays)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/messages` | All messages (streaming) |
| POST | `/messages` | Create message |
| GET | `/message/{id}` | Message details |
| PUT | `/message/{id}` | Update message |
| POST | `/message/{id}/trigger` | Display message |
| GET | `/message/{id}/clear` | Hide message |

### Looks
| Method | Path | Description |
|--------|------|-------------|
| GET | `/looks` | All saved looks |
| GET | `/look/current` | Live look (streaming) |
| PUT | `/look/current` | Update live look |
| GET | `/look/{id}/trigger` | Activate look |

### Macros
| Method | Path | Description |
|--------|------|-------------|
| GET | `/macros` | All macros |
| GET | `/macro/{id}/trigger` | Execute macro |

### Stage
| Method | Path | Description |
|--------|------|-------------|
| GET | `/stage/screens` | All stage screens |
| GET | `/stage/screens/{id}/layout` | Stage screen layout |
| GET | `/stage/layouts` | All stage layouts |
| GET | `/stage/message` | Current stage message |
| PUT | `/stage/message` | Set stage message |
| POST | `/stage/message/hide` | Hide stage message |

### Capture (Recording/Streaming)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/capture/status` | Capture status (streaming) |
| GET | `/capture/{operation}` | Start/stop capture |
| GET | `/capture/settings` | Capture settings |
| PUT | `/capture/settings` | Set capture settings |

### Audio/Media Playlists
| Method | Path | Description |
|--------|------|-------------|
| GET | `/audio/playlists` | Audio playlists |
| GET | `/audio/playlist/{id}/updates` | Audio playlist changes (streaming) |
| GET | `/media/playlists` | Media playlists |
| GET | `/media/playlist/{id}/updates` | Media playlist changes (streaming) |

### Video Inputs
| Method | Path | Description |
|--------|------|-------------|
| GET | `/video_inputs` | List video inputs |
| POST | `/video_inputs/{id}/trigger` | Trigger video input |

### Groups
| Method | Path | Description |
|--------|------|-------------|
| GET | `/groups` | All global groups |
| GET | `/group/{id}` | Trigger global group |

## Legacy WebSocket Protocol (Pre-7.9, still available)

Two WebSocket endpoints on the same network port:
- `ws://{host}:{port}/remote` — remote control
- `ws://{host}:{port}/stagedisplay` — stage display

Authentication (first message):
```json
{"action": "authenticate", "protocol": "701", "password": "your_password"}
```
Protocol: `701` for 7.4.2+, `700` for 7.0-7.4.1

## TCP/IP API

Same endpoints as HTTP, over raw TCP socket. Add `"chunked": true` for streaming:
```json
{"url": "v1/timer/system_time", "chunked": true}
```
Responses are line-delimited JSON:
```json
{"data": 1721367787, "url": "v1/timer/system_time"}
```

## Broadcast Integration Features
- **NDI output:** Native, configurable resolution/framerate, alpha channel support for keying
- **Syphon output:** macOS only, preserves alpha
- **Alpha Key:** NDI (toggle) and SDI (External Key with separate key/fill outputs)
- **Multi-screen:** Up to 16 outputs, each independently configurable
- **SMPTE Timecode:** Receive for external sync (version 7.10+)
- **MIDI:** Full send/receive, note mapping 0-127, network MIDI support
- **Capture:** Built-in H.264/H.265 recording, RTMP streaming
- **HDR:** Input and output support (version 21+)

## Key Integration Notes
1. HTTP API requires no authentication — accessible to any device on the network
2. WebSocket protocol (legacy) DOES require password authentication
3. Chunked HTTP is the official real-time monitoring mechanism (not SSE, not WebSocket)
4. `/v1/status/slide` is the primary endpoint for detecting slide changes
5. `{id}` parameters accept UUID, name, or numeric index (priority order)
6. Malformed WebSocket messages can crash ProPresenter — validate before sending
7. The `/v1/status/updates` aggregator is essential for monitoring multiple streams efficiently
