//
//  CameraAssignmentView.swift
//  Synaxis
//

import SwiftUI

// MARK: - Camera Assignment Row

struct CameraAssignmentRow: View {
    @Binding var camera: CameraAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Camera name with TSL index caption
                VStack(alignment: .leading, spacing: 2) {
                    Text(camera.name.isEmpty ? "Source \(camera.tslIndex)" : camera.name)
                        .fontWeight(.medium)
                    Text("TSL \(camera.tslIndex)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 120, alignment: .leading)

                Spacer()

                // HyperDeck input assignment (which ISO recording input this camera feeds)
                HStack(spacing: 4) {
                    Text("HyperDeck Input:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { camera.hyperDeckChannel ?? 0 },
                        set: { camera.hyperDeckChannel = $0 == 0 ? nil : $0 }
                    )) {
                        Text("None").tag(0)
                        ForEach(1...8, id: \.self) { ch in
                            Text("Input \(ch)").tag(ch)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
