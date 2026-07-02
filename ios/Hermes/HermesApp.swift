//
//  HermesApp.swift
//  Hermes
//

import SwiftUI

@main
struct HermesApp: App {
    @State private var appState = AppState()
    @State private var apiConfig = APIConfig()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        HermesBackgroundTasks.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(apiConfig)
                .onChange(of: scenePhase) { _, new in
                    appState.scenePhase = new
                    if new == .background {
                        HermesBackgroundTasks.scheduleRefresh()
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig

    var body: some View {
        Group {
            switch appState.authState {
            case .unconfigured, .misconfigured:
                FirstRunView()
            case .configured:
                SessionListView()
            }
        }
        .onChange(of: appState.authState) { _, newValue in
            if case .configured = newValue {
                apiConfig.reload()
            }
        }
        .onAppear {
            if KeychainStore.shared.isConfigured {
                apiConfig.reload()
            }
        }
    }
}
