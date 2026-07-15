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
        // Debug helper: if launched with `-autoConfigure <token>`, pre-fill the
        // keychain with the test gateway URL so we can verify SessionListView
        // appears without manual FirstRunView entry.
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-autoConfigureToken"),
           idx + 1 < args.count {
            let token = args[idx + 1]
            NSLog("[Hermes][Boot] -autoConfigureToken detected, prefilling keychain")
            KeychainStore.shared.gatewayURL = URL(string: "http://localhost:8080")
            KeychainStore.shared.bearerToken = token
            NSLog("[Hermes][Boot] isConfigured=%d", KeychainStore.shared.isConfigured ? 1 : 0)
        }
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
