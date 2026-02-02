# TSL 5.0 Implementation Notes

Derived from the existing iPhone Tally app (separate project).

## Proven Architecture

The tally app already has a working TSL 5 implementation talking to the Northwoods Ultrix Carbonite. Key decisions:

1. **The app listens as a TCP server** — the Carbonite is configured in DashBoard to send TSL data TO the Mac's IP:port
2. Uses Apple `Network` framework (`NWListener`, `NWConnection`)
3. Default TSL listener port: **5201**
4. Supports both **TSL 3.1 and TSL 5.0** with auto-detection

## TSL 5.0 Packet Format (as proven working)

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

## TSL 5.0 Detection Criteria

```swift
let bytes = [UInt8](dataBuffer.prefix(4))
let pbc = Int(bytes[0]) | (Int(bytes[1]) << 8)  // little-endian
let version = bytes[2]

// TSL 5.0 if:
// - PBC between 10 and 1000
// - version byte == 0x00
// - Buffer has enough data (pbc + 2 bytes)

// TSL 3.1 fallback if PBC > 1000 (fixed 18-byte messages)
```

## Control Byte Tally Extraction

```swift
// TSL 5.0 control field (16-bit, little-endian):
// Bits 0-1: RH Tally (Program/Red)     0=Off, 1=Red, 2=Green, 3=Amber
// Bits 2-3: Text Tally                 0=Off, 1=Red, 2=Green, 3=Amber
// Bits 4-5: LH Tally (Preview/Green)   0=Off, 1=Red, 2=Green, 3=Amber
// Bits 6-7: Brightness                 0-3

// HOWEVER, the tally app implementation maps differently:
let tally1 = control & 0x03         // Program (bits 0-1)
let tally2 = (control >> 2) & 0x03  // Preview (bits 2-3)
let isProgram = tally1 > 0   // Any brightness > 0 = active
let isPreview = tally2 > 0
```

**NOTE:** The tally app's bit mapping treats bits 0-1 as Program and bits 2-3 as Preview. This matches what the Carbonite actually sends, which may differ from the TSL 5.0 spec document ordering (RH/Text/LH). The real-world Carbonite behavior is what matters.

## TSL 3.1 Format (fallback)

```
Byte 0:      Address (0-126, 0-based)
Byte 1:      Control byte (same 2-bit-per-tally scheme)
Bytes 2-17:  16-char display text (ASCII, space-padded)
Total:       Fixed 18 bytes
```

Index conversion: `address + 1` (0-based to 1-based)

## TCP Stream Handling

The implementation uses a `dataBuffer: Data` that accumulates incoming bytes and processes complete messages in a loop. This is critical because TCP is stream-oriented — messages may arrive fragmented or concatenated.

```swift
// Accumulate
dataBuffer.append(data)

// Process all complete messages
while dataBuffer.count >= minimumSize {
    if isTSL5(dataBuffer) {
        parseTSL5()
    } else {
        parseTSL31()
    }
}
```

## Diagnostic Logging

Writes to `/tmp/tallyserver.log` with:
- Timestamps
- Raw hex dumps (first 40 bytes)
- Protocol detection decisions
- Parsed values (index, preview, program, text)

## Ross Carbonite Configuration

1. DashBoard > Configuration > Devices
2. Add Device > Type: TSL UMD > Driver: TSL 5
3. Set IP to Mac's address, port to 5201 (or configured port)
4. Save

## Key Constants

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

## What the Carbonite Sends

Label format: `source-index:bus-label:source-label`
Example: `0:ME1PGM:In 001` = source 0, ME1 Program bus, input "In 001"

Available bus labels include:
- PGM, PV, CLN (Program, Preview, Clean)
- ME1PGM, ME1PRV, ME1CLN (ME-specific)
- Aux 1-8
- MiniME buses

## Relevance to Touchdrive to Premiere

The Touchdrive app needs the same TSL 5 listener but extracts MORE data:
- Not just program/preview binary state, but which **source input** is on each bus
- Track keyer on/off states
- Track ME source selections over time (for timeline reconstruction)
- Parse the label text to extract bus name and source name
- Correlate TSL source indices with camera assignments

The tally app only cares about "is this source on program or preview?"
Touchdrive needs "which source just went to program on ME1?" — which requires tracking ALL TSL messages and correlating state changes over time.
