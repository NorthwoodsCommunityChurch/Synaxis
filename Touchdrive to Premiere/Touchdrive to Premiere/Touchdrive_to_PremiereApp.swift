//
//  SynaxisApp.swift
//  Synaxis
//
//  Created by Seth Potter on 1/28/26.
//

import SwiftUI

@main
struct SynaxisApp: App {

    // MARK: - Shared State

    @State private var settings = SettingsManager()
    @State private var assignments = AssignmentStore()
    @State private var connectionManager = ConnectionManager()
    @State private var sessionManager = SessionManager()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(assignments)
                .environment(connectionManager)
                .environment(sessionManager)
                .onAppear {
                    connectionManager.onEvent = { [sessionManager] event in
                        sessionManager.handleEvent(event)
                    }
                    // Auto-connect any enabled services on launch.
                    connectionManager.connectAll(settings: settings, assignments: assignments)
                }
                .onDisappear {
                    settings.save()
                }
        }

    }
}
