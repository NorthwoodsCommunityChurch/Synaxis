# HyperDeck Extreme 8K HDR — Integration Reference

## Product Overview
Blackmagic Design's flagship broadcast deck/recorder. 3 RU half-rack, 7" touchscreen (1920x1200, 2000-nit HDR, DCI-P3). Records SD through 8K. ~$5,945 USD.

## Codecs
| Codec | Variants | Max Resolution |
|-------|----------|----------------|
| Apple ProRes | HQ, 422, LT, Proxy | 8K 4320p60 |
| H.265 (HEVC) | High, Medium, Low (10-bit 4:2:0) | 8K 4320p60 |
| H.264 | High, Medium, Low | 1080p60 |
| DNxHD / DNxHR | Various | 2160p |

Containers: QuickTime (.mov), MKV

## I/O Connections
- **Video In:** 4x 12G-SDI (Quad Link for 8K), 1x HDMI 2.0, Component YUV, Composite
- **Video Out:** 5x 12G-SDI (A/B/C/D + 1x 3G monitor), 1x HDMI 2.0
- **Audio:** 4ch balanced XLR, 2ch RCA, 64ch SDI embedded, 8ch HDMI embedded (48kHz 24-bit)
- **Timecode:** XLR in + XLR out
- **Control:** 2x RS-422 DB9, 10Gb Ethernet, USB-C
- **Reference:** Tri-Sync / Black Burst in + loop out
- **Storage:** 2x CFast 2.0, 1x M.2 NVMe (internal cache), USB-C 3.1 Gen 2, Network (10G Ethernet)

## Resolution & Frame Rate Support
- SD: 525i59.94, 625i50
- HD: 720p50/59.94/60, 1080i50/59.94/60, 1080p23.98-60
- UHD: 2160p23.98-60
- 4K DCI: 2160p23.98/24/25
- 8K UHD: 4320p23.98-60
- 8K DCI: 4320p23.98/24/25

## Ethernet Protocol (TCP Port 9993)

### Connection
- Text-based TCP, port 9993
- Line termination: server sends `\r\n`, client may send `\n` or `\r\n`
- On connect: `500 connection info:` with protocol version and model

### Key Commands

**Transport:**
| Command | Parameters |
|---------|-----------|
| `play` | `speed: {-5000..5000}`, `loop: {true/false}`, `single clip: {true/false}` |
| `stop` | (none) |
| `record` | `name: {clipname}` |
| `record spill` | `slot id: {n}` |
| `goto` | `clip id: {n/+n/-n}`, `clip: {start/end}`, `timecode: {TC}`, `slot id: {n}` |
| `jog` | `timecode: {TC}` |
| `shuttle` | `speed: {-5000..5000}` |

**Clips:**
| Command | Description |
|---------|-------------|
| `clips get` | Get timeline clip list (v1) |
| `clips get: version: 2` | + clip IDs, in/out points |
| `clips get: version: 3` | + full file path |
| `clips count` | Return clip count |
| `disk list` | List all clips on disk |

**Configuration:**
| Command | Values |
|---------|--------|
| `configuration: video input:` | `SDI`, `HDMI`, `component`, `composite` |
| `configuration: audio input:` | `embedded`, `XLR`, `RCA` |
| `configuration: file format:` | codec/format string |
| `configuration: timecode input:` | `external`, `embedded`, `preset`, `clip`, `internal` |
| `configuration: timecode output:` | `clip`, `timeline` |
| `configuration: timecode preference:` | `default`, `dropframe`, `nondropframe` |
| `configuration: timecode preset:` | `HH:MM:SS:FF` |
| `configuration: record prefix:` | filename prefix (UTF-8) |
| `configuration: record trigger:` | `none`, `recordbit`, `timecoderun` |

**Queries:**
| Command | Response Code |
|---------|--------------|
| `device info` | 204 |
| `transport info` | 208 |
| `slot info` | 202 |
| `configuration` | 211 |

### Async Notifications
Enable: `notify: transport: true slot: true configuration: true`

All categories: `transport`, `slot`, `remote`, `configuration`, `dropped frames`, `display timecode`, `timeline position`, `playrange`, `cache`, `dynamic range`, `slate`

| Event | Async Code |
|-------|-----------|
| Transport change | `508 transport info:` |
| Slot change | `502 slot info:` |
| Remote change | `510 remote info:` |
| Config change | `511 configuration:` |

### Transport States
`preview`, `stopped`, `play`, `forward`, `rewind`, `jog`, `shuttle`, `record`

### Transport Info Fields
```
status: record
speed: 0
slot id: 3
slot name: network/Test
clip id: 1
single clip: false
display timecode: 09:19:34;22
timecode: 00:00:00;20
video format: 1080p5994
loop: false
timeline: 1
input video format: 1080p5994
dynamic range: Rec709
reference locked: false
```

### Response Codes
**Success:** 200 OK, 202 slot info, 204 device info, 205 clips info, 206 disk list, 208 transport info, 209 notify, 210 remote, 211 configuration
**Failure:** 100 syntax error, 101 unsupported param, 102 invalid value, 103 unsupported command, 104 disk full, 105 no disk, 106 disk error, 107 timeline empty, 108 internal error, 109 out of range, 110 no input, 111 remote disabled, 112 clip not found
**Async:** 500 connection info, 502 slot, 508 transport, 510 remote, 511 configuration

### Timecode Format
- Non-drop-frame: `HH:MM:SS:FF` (colons)
- Drop-frame: `HH:MM:SS;FF` (semicolons)

## REST API (HTTP)

Base URL: `http://{IP}/control/api/v1/`

| Group | Key Endpoints |
|-------|--------------|
| Transport | `GET/PUT /transports/0`, `POST .../stop`, `POST .../play`, `POST .../record` |
| System | `GET /system`, `GET/PUT /system/codecFormat`, `GET/PUT /system/videoFormat` |
| Media | `GET /media/workingset`, `GET/PUT /media/active` |
| Timeline | `GET /timelines/0`, `POST /timelines/0` (add clips), `DELETE /timelines/0` (clear) |

**WebSocket Events:** `ws://{IP}/control/api/v1/event/websocket` — JSON notifications for transport, media, system, timeline changes.

## Extreme 8K-Specific Features (vs Studio)
- 7" 2000-nit HDR touchscreen with built-in broadcast scopes
- 3D LUT loading for on-screen monitoring
- M.2 NVMe cache recording (eliminates dropped frames)
- 4-channel simultaneous SDI recording (4x 2160p60 ISOs)
- 10 Gigabit Ethernet (vs 1G on most Studio models)
- Analog video I/O (component, composite)
- XLR balanced + RCA unbalanced audio
- HDR-aware scopes (waveform, parade, vectorscope, histogram)

## File Naming
- Default prefix: `HyperDeck_XXXX` (e.g., `HyperDeck_0001.mov`)
- Custom: `record: name: {clipname}` or `configuration: record prefix: {name}`
- Optional timestamp suffix: `configuration: append timestamp: true`

## Clip List Format (clips get)
```
205 clips info:
clip count: 2
1: HyperDeck_0003.mov 00:00:00;00 00:00:06;00
2: HyperDeck_0004.mov 00:00:06;00 00:00:04;15
```
