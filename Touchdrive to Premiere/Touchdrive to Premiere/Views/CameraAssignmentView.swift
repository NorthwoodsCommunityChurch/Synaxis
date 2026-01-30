//
//  CameraAssignmentView.swift
//  Synaxis
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Camera Assignment Row

struct CameraAssignmentRow: View {
    @Binding var camera: CameraAssignment

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            // TSL source index
            Stepper(value: $camera.tslIndex, in: 1...99) {
                Text("TSL \(camera.tslIndex)")
                    .frame(width: 60, alignment: .leading)
            }

            // Display name
            TextField("Name", text: $camera.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            // File URL with drag/drop and browse
            HStack {
                Text(camera.fileURL?.lastPathComponent ?? "No file selected")
                    .foregroundColor(camera.fileURL == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: browseFile) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)

                if camera.fileURL != nil {
                    Button(action: { camera.fileURL = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(4)
            .background(isTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            // HyperDeck channel picker (optional, 1-4)
            Picker("HD Ch", selection: Binding(
                get: { camera.hyperDeckChannel ?? 0 },
                set: { camera.hyperDeckChannel = $0 == 0 ? nil : $0 }
            )) {
                Text("None").tag(0)
                ForEach(1...4, id: \.self) { ch in
                    Text("Ch \(ch)").tag(ch)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
        }
        .padding(.vertical, 4)
    }

    // MARK: - File Browsing

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.movie,
            UTType.video,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType(filenameExtension: "mxf") ?? .movie,
        ]

        if panel.runModal() == .OK, let url = panel.url {
            camera.fileURL = url
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    camera.fileURL = url
                }
            }
        }
        return true
    }
}
