//
//  KeyerAssignmentView.swift
//  Synaxis
//

import SwiftUI

// MARK: - Keyer Assignment Row

struct KeyerAssignmentRow: View {
    @Binding var keyer: KeyerAssignment

    var body: some View {
        HStack(spacing: 12) {
            // ME number picker (1-4)
            Picker("ME", selection: $keyer.meNumber) {
                ForEach(1...4, id: \.self) { me in
                    Text("ME \(me)").tag(me)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)

            // Keyer number stepper (1-8)
            Stepper(value: $keyer.keyerNumber, in: 1...8) {
                Text("Key \(keyer.keyerNumber)")
                    .frame(width: 55, alignment: .leading)
            }

            // Label text field
            TextField("Label", text: $keyer.label)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            // Source picker
            Picker("Source", selection: $keyer.source) {
                ForEach(KeyerSource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .padding(.vertical, 4)
    }
}
