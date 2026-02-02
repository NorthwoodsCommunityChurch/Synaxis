//
//  PremiereXMLGenerator.swift
//  Synaxis
//
//  Created by Seth Potter on 1/28/26.
//

import Foundation
import OSLog

/// Generates xmeml v4 (FCP 7 interchange) XML files for Adobe Premiere Pro import.
///
/// Uses `Foundation.XMLDocument` for proper XML construction and escaping.
///
/// Track layout:
///   - V1:    Program cut (clips from whichever camera is on program)
///   - V2-V4: ISO tracks (one per camera assignment, full-length clips)
///   - V5:    Graphics track (ProPresenter slide clips, only while keyer is ON)
///   - A1-A4: Audio tracks paired with V1-V4
struct PremiereXMLGenerator {

    // MARK: - Properties

    private let session: ProductionSession

    /// Precomputed values derived from session settings.
    private let timebaseValue: Int
    private let isNTSCValue: Bool
    private let useDropFrame: Bool
    private let startFrameOffset: Int
    private let sessionDurationFrames: Int

    /// Counters for clip item ID uniqueness.
    private var clipItemCounter: Int = 0

    // MARK: - Initialization

    init(session: ProductionSession) {
        self.session = session
        self.timebaseValue = TimecodeHelpers.timebase(for: session.frameRate)
        self.isNTSCValue = TimecodeHelpers.isNTSC(session.frameRate)
        self.useDropFrame = session.dropFrame && TimecodeHelpers.supportsDropFrame(session.frameRate)
        self.startFrameOffset = TimecodeHelpers.stringToFrames(
            session.startTimecode,
            frameRate: session.frameRate,
            dropFrame: session.dropFrame
        ) ?? 0
        self.sessionDurationFrames = {
            let endDate = session.endTime ?? session.events.last?.timestamp ?? session.startTime
            return TimecodeHelpers.dateToFrames(endDate, sessionStart: session.startTime, frameRate: session.frameRate)
        }()
    }

    // MARK: - Public API

    /// The total number of video and audio tracks that will be generated.
    var trackCount: Int {
        let cameraCount = session.cameraAssignments.count
        // V1 (program) + ISO tracks (one per camera) + graphics track
        let videoTracks = 1 + cameraCount + 1
        // A1 (program audio) + one audio per ISO
        let audioTracks = 1 + cameraCount
        return videoTracks + audioTracks
    }

    /// The number of sequence-level markers that will be generated.
    var markerCount: Int {
        session.events.filter { event in
            switch event.type {
            case .keyerOn, .keyerOff, .slideChange:
                return true
            default:
                return false
            }
        }.count
    }

    /// Generate the complete xmeml v4 XML as a string.
    mutating func generateXML() -> String {
        let doc = generateXMLDocument()
        let opts: XMLNode.Options = [.nodePrettyPrint, .nodeCompactEmptyElement]
        return doc.xmlString(options: opts)
    }

    /// Generate the complete xmeml v4 XML as an `XMLDocument`.
    mutating func generateXMLDocument() -> XMLDocument {
        clipItemCounter = 0

        let doc = XMLDocument(rootElement: nil)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        doc.dtd = XMLDTD()
        doc.dtd?.name = "xmeml"

        let root = XMLElement(name: "xmeml")
        root.setAttributesWith(["version": "4"])
        doc.setRootElement(root)

        let sequence = buildSequence()
        root.addChild(sequence)

        let tc = trackCount
        let mc = markerCount
        Log.export.info("Generated xmeml v4 document with \(tc) tracks and \(mc) markers")

        return doc
    }

    /// Save the generated XML to a file at the given URL.
    mutating func saveToFile(at url: URL) throws {
        let xmlString = generateXML()
        try xmlString.write(to: url, atomically: true, encoding: .utf8)
        Log.export.info("Saved Premiere XML to \(url.path)")
    }

    // MARK: - Sequence

    private mutating func buildSequence() -> XMLElement {
        let seq = XMLElement(name: "sequence")

        seq.addChild(textElement("name", value: session.name))
        seq.addChild(textElement("duration", value: "\(sessionDurationFrames)"))
        seq.addChild(buildRate())
        seq.addChild(buildSequenceTimecode())

        // Sequence-level markers
        for marker in buildSequenceMarkers() {
            seq.addChild(marker)
        }

        seq.addChild(buildMedia())

        return seq
    }

    // MARK: - Rate

    private func buildRate() -> XMLElement {
        let rate = XMLElement(name: "rate")
        rate.addChild(textElement("timebase", value: "\(timebaseValue)"))
        rate.addChild(textElement("ntsc", value: isNTSCValue ? "TRUE" : "FALSE"))
        return rate
    }

    // MARK: - Format

    private func buildFormat() -> XMLElement {
        let format = XMLElement(name: "format")
        let sc = XMLElement(name: "samplecharacteristics")
        sc.addChild(textElement("width", value: "\(session.resolution.width)"))
        sc.addChild(textElement("height", value: "\(session.resolution.height)"))
        sc.addChild(textElement("anamorphic", value: "FALSE"))
        sc.addChild(textElement("pixelaspectratio", value: "Square"))
        sc.addChild(textElement("fielddominance", value: "none"))
        sc.addChild(buildRate())
        format.addChild(sc)
        return format
    }

    // MARK: - Timecode

    private func buildSequenceTimecode() -> XMLElement {
        let tc = XMLElement(name: "timecode")
        tc.addChild(textElement("string", value: session.startTimecode))
        tc.addChild(textElement("frame", value: "\(startFrameOffset)"))
        tc.addChild(textElement("displayformat", value: useDropFrame ? "DF" : "NDF"))
        tc.addChild(buildRate())
        return tc
    }

    // MARK: - Markers

    private func buildSequenceMarkers() -> [XMLElement] {
        var markers: [XMLElement] = []

        for event in session.events {
            switch event.type {
            case .keyerOn:
                guard let keyerNum = event.payload.keyerNumber,
                      let meNum = event.payload.meNumber else { continue }
                let frame = eventFrame(event)
                let marker = XMLElement(name: "marker")
                marker.addChild(textElement("comment", value: "Keyer \(keyerNum) ON (ME\(meNum))"))
                marker.addChild(textElement("name", value: "Keyer ON"))
                marker.addChild(textElement("in", value: "\(frame)"))
                marker.addChild(textElement("out", value: "-1"))
                markers.append(marker)

            case .keyerOff:
                guard let keyerNum = event.payload.keyerNumber,
                      let meNum = event.payload.meNumber else { continue }
                let frame = eventFrame(event)
                let marker = XMLElement(name: "marker")
                marker.addChild(textElement("comment", value: "Keyer \(keyerNum) OFF (ME\(meNum))"))
                marker.addChild(textElement("name", value: "Keyer OFF"))
                marker.addChild(textElement("in", value: "\(frame)"))
                marker.addChild(textElement("out", value: "-1"))
                markers.append(marker)

            case .slideChange:
                guard let presentation = event.payload.presentationName,
                      let slideIdx = event.payload.slideIndex else { continue }
                let slideText = event.payload.slideText ?? ""
                let frame = eventFrame(event)
                let marker = XMLElement(name: "marker")
                let comment = slideText.isEmpty
                    ? "\(presentation) - Slide \(slideIdx + 1)"
                    : "\(presentation) - Slide \(slideIdx + 1): \(slideText)"
                marker.addChild(textElement("comment", value: comment))
                marker.addChild(textElement("name", value: "Slide Change"))
                marker.addChild(textElement("in", value: "\(frame)"))
                marker.addChild(textElement("out", value: "-1"))
                markers.append(marker)

            default:
                break
            }
        }

        return markers
    }

    // MARK: - Media

    private mutating func buildMedia() -> XMLElement {
        let media = XMLElement(name: "media")
        media.addChild(buildVideo())
        media.addChild(buildAudio())
        return media
    }

    // MARK: - Video

    private mutating func buildVideo() -> XMLElement {
        let video = XMLElement(name: "video")
        video.addChild(buildFormat())

        // V1: Program cut track
        video.addChild(buildProgramCutTrack())

        // V2-V(N+1): ISO tracks, one per camera
        for camera in session.cameraAssignments {
            video.addChild(buildISOTrack(camera: camera))
        }

        // V(N+2): Graphics track
        video.addChild(buildGraphicsTrack())

        return video
    }

    // MARK: - Audio

    private mutating func buildAudio() -> XMLElement {
        let audio = XMLElement(name: "audio")
        audio.addChild(textElement("numOutputChannels", value: "2"))

        // A1: Program cut audio
        audio.addChild(buildProgramCutAudioTrack())

        // A2-A(N+1): ISO audio, one per camera
        for camera in session.cameraAssignments {
            audio.addChild(buildISOAudioTrack(camera: camera))
        }

        return audio
    }

    // MARK: - V1: Program Cut Track

    private mutating func buildProgramCutTrack() -> XMLElement {
        let track = XMLElement(name: "track")

        let cuts = programCutSegments()

        for segment in cuts {
            // Use configured camera if available; fall back to a placeholder
            // so cuts always appear in the XML even without camera assignments.
            let camera = cameraForSourceIndex(segment.sourceIndex)
                ?? CameraAssignment(tslIndex: segment.sourceIndex, name: segment.sourceName)

            let timelineIn = segment.startFrame + startFrameOffset
            let timelineOut = segment.endFrame + startFrameOffset
            // Source in/out: the portion of the source file that corresponds to this timeline region.
            // Since the source file covers the entire session, source in/out equals the raw event frames.
            let sourceIn = segment.startFrame
            let sourceOut = segment.endFrame
            let duration = sessionDurationFrames

            let clipitem = buildClipItem(
                camera: camera,
                timelineIn: timelineIn,
                timelineOut: timelineOut,
                sourceIn: sourceIn,
                sourceOut: sourceOut,
                duration: duration,
                isVideo: true
            )
            track.addChild(clipitem)
        }

        track.addChild(textElement("enabled", value: "TRUE"))
        track.addChild(textElement("locked", value: "FALSE"))

        return track
    }

    // MARK: - V2-V4: ISO Tracks

    private mutating func buildISOTrack(camera: CameraAssignment) -> XMLElement {
        let track = XMLElement(name: "track")

        let timelineIn = startFrameOffset
        let timelineOut = sessionDurationFrames + startFrameOffset
        let sourceIn = 0
        let sourceOut = sessionDurationFrames
        let duration = sessionDurationFrames

        let clipitem = buildClipItem(
            camera: camera,
            timelineIn: timelineIn,
            timelineOut: timelineOut,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            duration: duration,
            isVideo: true
        )
        track.addChild(clipitem)

        track.addChild(textElement("enabled", value: "TRUE"))
        track.addChild(textElement("locked", value: "FALSE"))

        return track
    }

    // MARK: - V5: Graphics Track

    private mutating func buildGraphicsTrack() -> XMLElement {
        let track = XMLElement(name: "track")

        let segments = graphicsSegments()

        for segment in segments {
            let timelineIn = segment.startFrame + startFrameOffset
            let timelineOut = segment.endFrame + startFrameOffset
            let sourceIn = 0
            let sourceOut = segment.endFrame - segment.startFrame
            let duration = sourceOut

            let clipitem = buildGraphicsClipItem(
                name: segment.clipName,
                timelineIn: timelineIn,
                timelineOut: timelineOut,
                sourceIn: sourceIn,
                sourceOut: sourceOut,
                duration: duration
            )
            track.addChild(clipitem)
        }

        track.addChild(textElement("enabled", value: "TRUE"))
        track.addChild(textElement("locked", value: "FALSE"))

        return track
    }

    // MARK: - A1: Program Cut Audio Track

    private mutating func buildProgramCutAudioTrack() -> XMLElement {
        let track = XMLElement(name: "track")

        let cuts = programCutSegments()

        for segment in cuts {
            let camera = cameraForSourceIndex(segment.sourceIndex)
                ?? CameraAssignment(tslIndex: segment.sourceIndex, name: segment.sourceName)

            let timelineIn = segment.startFrame + startFrameOffset
            let timelineOut = segment.endFrame + startFrameOffset
            let sourceIn = segment.startFrame
            let sourceOut = segment.endFrame
            let duration = sessionDurationFrames

            let clipitem = buildClipItem(
                camera: camera,
                timelineIn: timelineIn,
                timelineOut: timelineOut,
                sourceIn: sourceIn,
                sourceOut: sourceOut,
                duration: duration,
                isVideo: false
            )
            track.addChild(clipitem)
        }

        return track
    }

    // MARK: - A2-A4: ISO Audio Tracks

    private mutating func buildISOAudioTrack(camera: CameraAssignment) -> XMLElement {
        let track = XMLElement(name: "track")

        let timelineIn = startFrameOffset
        let timelineOut = sessionDurationFrames + startFrameOffset
        let sourceIn = 0
        let sourceOut = sessionDurationFrames
        let duration = sessionDurationFrames

        let clipitem = buildClipItem(
            camera: camera,
            timelineIn: timelineIn,
            timelineOut: timelineOut,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            duration: duration,
            isVideo: false
        )
        track.addChild(clipitem)

        return track
    }

    // MARK: - Clip Item Builders

    /// Build a video or audio clip item element referencing a camera's file.
    private mutating func buildClipItem(
        camera: CameraAssignment,
        timelineIn: Int,
        timelineOut: Int,
        sourceIn: Int,
        sourceOut: Int,
        duration: Int,
        isVideo: Bool
    ) -> XMLElement {
        clipItemCounter += 1
        let itemId = "clipitem-\(clipItemCounter)"
        let masterclipId = masterClipId(for: camera)
        let fileId = fileElementId(for: camera)

        let clipitem = XMLElement(name: "clipitem")
        clipitem.setAttributesWith(["id": itemId])

        clipitem.addChild(textElement("masterclipid", value: masterclipId))
        clipitem.addChild(textElement("name", value: camera.name))
        clipitem.addChild(textElement("enabled", value: "TRUE"))
        clipitem.addChild(textElement("duration", value: "\(duration)"))
        clipitem.addChild(buildRate())
        clipitem.addChild(textElement("start", value: "\(timelineIn)"))
        clipitem.addChild(textElement("end", value: "\(timelineOut)"))
        clipitem.addChild(textElement("in", value: "\(sourceIn)"))
        clipitem.addChild(textElement("out", value: "\(sourceOut)"))

        if isVideo {
            // Full file element for video clips (first reference defines the file)
            let fileEl = buildFileElement(camera: camera, fileId: fileId)
            clipitem.addChild(fileEl)
        } else {
            // Audio clip: reference-only file element + sourcetrack
            let fileRef = XMLElement(name: "file")
            fileRef.setAttributesWith(["id": fileId])
            clipitem.addChild(fileRef)

            let sourcetrack = XMLElement(name: "sourcetrack")
            sourcetrack.addChild(textElement("mediatype", value: "audio"))
            sourcetrack.addChild(textElement("trackindex", value: "1"))
            clipitem.addChild(sourcetrack)
        }

        return clipitem
    }

    /// Build a graphics clip item element (not tied to a camera file).
    private mutating func buildGraphicsClipItem(
        name: String,
        timelineIn: Int,
        timelineOut: Int,
        sourceIn: Int,
        sourceOut: Int,
        duration: Int
    ) -> XMLElement {
        clipItemCounter += 1
        let itemId = "clipitem-\(clipItemCounter)"

        let clipitem = XMLElement(name: "clipitem")
        clipitem.setAttributesWith(["id": itemId])

        clipitem.addChild(textElement("masterclipid", value: "masterclip-graphics"))
        clipitem.addChild(textElement("name", value: name))
        clipitem.addChild(textElement("enabled", value: "TRUE"))
        clipitem.addChild(textElement("duration", value: "\(duration)"))
        clipitem.addChild(buildRate())
        clipitem.addChild(textElement("start", value: "\(timelineIn)"))
        clipitem.addChild(textElement("end", value: "\(timelineOut)"))
        clipitem.addChild(textElement("in", value: "\(sourceIn)"))
        clipitem.addChild(textElement("out", value: "\(sourceOut)"))

        let fileRef = XMLElement(name: "file")
        fileRef.setAttributesWith(["id": "file-graphics"])
        clipitem.addChild(fileRef)

        return clipitem
    }

    // MARK: - File Element

    /// Build a `<file>` element with full metadata for a camera source.
    private func buildFileElement(camera: CameraAssignment, fileId: String) -> XMLElement {
        let fileEl = XMLElement(name: "file")
        fileEl.setAttributesWith(["id": fileId])

        if let url = camera.fileURL {
            fileEl.addChild(textElement("name", value: url.lastPathComponent))
            fileEl.addChild(textElement("pathurl", value: url.absoluteString))
        } else {
            fileEl.addChild(textElement("name", value: camera.name))
        }

        fileEl.addChild(textElement("duration", value: "\(sessionDurationFrames)"))
        fileEl.addChild(buildRate())

        let media = XMLElement(name: "media")

        // Video media
        let videoMedia = XMLElement(name: "video")
        videoMedia.addChild(buildFormat())
        media.addChild(videoMedia)

        // Audio media
        let audioMedia = XMLElement(name: "audio")
        let audioFormat = XMLElement(name: "samplecharacteristics")
        audioFormat.addChild(textElement("samplerate", value: "48000"))
        audioFormat.addChild(textElement("depth", value: "16"))
        audioMedia.addChild(audioFormat)
        media.addChild(audioMedia)

        fileEl.addChild(media)

        return fileEl
    }

    // MARK: - Program Cut Segments

    /// A segment representing a contiguous region on the program bus for one source.
    private struct CutSegment {
        let sourceIndex: Int
        let sourceName: String
        let startFrame: Int
        let endFrame: Int
    }

    /// Parse events to produce program cut segments for V1.
    private func programCutSegments() -> [CutSegment] {
        var segments: [CutSegment] = []

        // Gather all program cut and transition events, sorted by timestamp.
        let cutEvents = session.events.filter { event in
            event.type == .programCut || event.type == .transition
        }

        guard !cutEvents.isEmpty else { return segments }

        for (index, event) in cutEvents.enumerated() {
            guard let sourceIdx = event.payload.sourceIndex else { continue }

            let startFrame = TimecodeHelpers.dateToFrames(
                event.timestamp,
                sessionStart: session.startTime,
                frameRate: session.frameRate
            )

            let endFrame: Int
            if index + 1 < cutEvents.count {
                endFrame = TimecodeHelpers.dateToFrames(
                    cutEvents[index + 1].timestamp,
                    sessionStart: session.startTime,
                    frameRate: session.frameRate
                )
            } else {
                endFrame = sessionDurationFrames
            }

            if endFrame > startFrame {
                segments.append(CutSegment(
                    sourceIndex: sourceIdx,
                    sourceName: event.payload.sourceName ?? "Source \(sourceIdx)",
                    startFrame: startFrame,
                    endFrame: endFrame
                ))
            }
        }

        return segments
    }

    // MARK: - Graphics Segments

    /// A segment representing a graphics clip visible on the timeline.
    private struct GraphicsSegment {
        let clipName: String
        let startFrame: Int
        let endFrame: Int
    }

    /// Parse events to produce graphics segments for V5.
    /// Graphics clips appear only while a keyer is ON.
    private func graphicsSegments() -> [GraphicsSegment] {
        var segments: [GraphicsSegment] = []

        // Track state per keyer (by keyerNumber).
        // Value: (isOn, onTimestamp, currentPresentation, currentSlideIndex, currentSlideText)
        struct KeyerState {
            var isOn: Bool = false
            var segmentStartFrame: Int = 0
            var presentation: String?
            var slideIndex: Int?
            var slideText: String?
        }

        var keyerStates: [Int: KeyerState] = [:]

        // Initialize keyer states from assignments.
        for assignment in session.keyerAssignments {
            keyerStates[assignment.keyerNumber] = KeyerState()
        }

        for event in session.events {
            switch event.type {
            case .keyerOn:
                guard let keyerNum = event.payload.keyerNumber else { continue }
                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: session.frameRate
                )
                var state = keyerStates[keyerNum] ?? KeyerState()
                state.isOn = true
                state.segmentStartFrame = frame
                keyerStates[keyerNum] = state

            case .keyerOff:
                guard let keyerNum = event.payload.keyerNumber else { continue }
                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: session.frameRate
                )
                guard var state = keyerStates[keyerNum], state.isOn else { continue }

                if frame > state.segmentStartFrame {
                    let name = buildSlideClipName(
                        presentation: state.presentation,
                        slideIndex: state.slideIndex,
                        slideText: state.slideText,
                        keyerNumber: keyerNum
                    )
                    segments.append(GraphicsSegment(
                        clipName: name,
                        startFrame: state.segmentStartFrame,
                        endFrame: frame
                    ))
                }
                state.isOn = false
                state.segmentStartFrame = 0
                keyerStates[keyerNum] = state

            case .slideChange:
                guard let slideIdx = event.payload.slideIndex,
                      let presentation = event.payload.presentationName else { continue }
                let slideText = event.payload.slideText

                // Find which keyer this slide change applies to.
                // Match to any keyer that is ProPresenter-sourced, or fall back to keyer 1.
                let matchingKeyerNum = session.keyerAssignments
                    .first(where: { $0.source == .proPresenter })?.keyerNumber ?? 1

                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: session.frameRate
                )

                if var state = keyerStates[matchingKeyerNum], state.isOn {
                    // Close out current segment
                    if frame > state.segmentStartFrame {
                        let name = buildSlideClipName(
                            presentation: state.presentation,
                            slideIndex: state.slideIndex,
                            slideText: state.slideText,
                            keyerNumber: matchingKeyerNum
                        )
                        segments.append(GraphicsSegment(
                            clipName: name,
                            startFrame: state.segmentStartFrame,
                            endFrame: frame
                        ))
                    }
                    // Start new segment with updated slide info
                    state.segmentStartFrame = frame
                    state.presentation = presentation
                    state.slideIndex = slideIdx
                    state.slideText = slideText
                    keyerStates[matchingKeyerNum] = state
                } else {
                    // Keyer is off; just update the slide info so it is ready for when keyer turns on.
                    var state = keyerStates[matchingKeyerNum] ?? KeyerState()
                    state.presentation = presentation
                    state.slideIndex = slideIdx
                    state.slideText = slideText
                    keyerStates[matchingKeyerNum] = state
                }

            default:
                break
            }
        }

        return segments
    }

    // MARK: - Helpers

    /// Build a descriptive name for a graphics/slide clip.
    private func buildSlideClipName(
        presentation: String?,
        slideIndex: Int?,
        slideText: String?,
        keyerNumber: Int
    ) -> String {
        var parts: [String] = []

        if let presentation = presentation, !presentation.isEmpty {
            parts.append(presentation)
        }

        if let index = slideIndex {
            parts.append("Slide \(index + 1)")
        }

        if let text = slideText, !text.isEmpty {
            let truncated = text.count > 30 ? String(text.prefix(30)) + "..." : text
            parts.append(truncated)
        }

        if parts.isEmpty {
            return "Keyer \(keyerNumber)"
        }

        return parts.joined(separator: " - ")
    }

    /// Find the camera assignment matching a TSL source index.
    private func cameraForSourceIndex(_ sourceIndex: Int) -> CameraAssignment? {
        session.cameraAssignments.first(where: { $0.tslIndex == sourceIndex })
    }

    /// Compute a stable master clip ID for a camera.
    private func masterClipId(for camera: CameraAssignment) -> String {
        "masterclip-cam\(camera.tslIndex)"
    }

    /// Compute a stable file element ID for a camera.
    private func fileElementId(for camera: CameraAssignment) -> String {
        "file-cam\(camera.tslIndex)"
    }

    /// Convert an event's timestamp to a timeline frame number (including startFrameOffset).
    private func eventFrame(_ event: ProductionEvent) -> Int {
        TimecodeHelpers.dateToFrames(
            event.timestamp,
            sessionStart: session.startTime,
            frameRate: session.frameRate
        ) + startFrameOffset
    }

    /// Create a simple text-content XML element.
    private func textElement(_ name: String, value: String) -> XMLElement {
        let el = XMLElement(name: name)
        el.stringValue = value
        return el
    }
}
