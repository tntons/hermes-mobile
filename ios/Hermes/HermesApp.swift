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
        #if DEBUG
        // Debug helpers for headless verification of the FirstRunView →
        // SessionListView → ConversationView flow without manual typing.
        // Run via:
        //   xcrun simctl launch booted com.hermes.mobile \
        //     -autoConfigureToken <hex> [-openFirstSession]
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-autoConfigureToken"),
           idx + 1 < args.count {
            KeychainStore.shared.gatewayURL = URL(string: "http://localhost:8080")
            KeychainStore.shared.bearerToken = args[idx + 1]
        }
        if args.contains("-openFirstSession") {
            UserDefaults.standard.set(true, forKey: "_debug.openFirstSession")
        }
        #endif
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
            appState.reloadAuth()
            if KeychainStore.shared.isConfigured {
                apiConfig.reload()
            }
        }
    }
}
