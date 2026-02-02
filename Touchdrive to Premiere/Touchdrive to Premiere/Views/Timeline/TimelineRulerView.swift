//
//  TimelineRulerView.swift
//  Synaxis
//
//  Draws timecode tick marks along the top of the timeline canvas.
//

import SwiftUI

struct TimelineRulerView: View {
    let durationFrames: Int
    let pixelsPerFrame: Double
    let frameRate: Double
    let dropFrame: Bool
    let startTimecode: String

    var body: some View {
        Canvas { context, size in
            let startOffset = TimecodeHelpers.stringToFrames(
                startTimecode, frameRate: frameRate, dropFrame: dropFrame
            ) ?? 0

            let pixelsPerSecond = pixelsPerFrame * frameRate
            let tickIntervalSeconds = calculateTickInterval(pixelsPerSecond: pixelsPerSecond)
            let tickIntervalFrames = max(1, Int(tickIntervalSeconds * frameRate))

            var frame = 0
            while frame <= durationFrames {
                let x = Double(frame) * pixelsPerFrame

                // Major tick line
                let tickPath = Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - 10))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(tickPath, with: .color(.secondary), lineWidth: 1)

                // Timecode label
                let absoluteFrame = frame + startOffset
                let label = TimecodeHelpers.framesToString(
                    absoluteFrame, frameRate: frameRate, dropFrame: dropFrame
                )
                let text = Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                let resolvedText = context.resolve(text)
                let labelY = size.height / 2.0 - 1.0
                context.draw(resolvedText, at: CGPoint(x: x + 4, y: labelY), anchor: .leading)

                frame += tickIntervalFrames
            }

            // Bottom border line
            let borderPath = Path { p in
                p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            }
            context.stroke(borderPath, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Adaptive tick interval based on zoom level.
    private func calculateTickInterval(pixelsPerSecond: Double) -> Double {
        if pixelsPerSecond > 200 { return 1 }
        if pixelsPerSecond > 50 { return 5 }
        if pixelsPerSecond > 20 { return 10 }
        if pixelsPerSecond > 5 { return 30 }
        return 60
    }
}
