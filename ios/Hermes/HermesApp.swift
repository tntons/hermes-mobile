//
//  HermesApp.swift
//  Hermes
//

import SwiftUI

enum HermesTheme {
    static let background = Color(red: 0.125, green: 0.125, blue: 0.125)
    static let surface = Color(red: 0.180, green: 0.180, blue: 0.180)
    static let surfaceElevated = Color(red: 0.220, green: 0.220, blue: 0.220)
    static let userBubble = Color(red: 0.184, green: 0.184, blue: 0.184)
    static let border = Color.white.opacity(0.12)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.42)
    static let accent = Color(red: 0.42, green: 0.82, blue: 0.60)
    static let accentSoft = Color(red: 0.25, green: 0.50, blue: 0.37)
}

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
        if !KeychainStore.shared.isConfigured {
            KeychainStore.shared.isMockMode = true
            KeychainStore.shared.profile = "demo"
        }
        if let idx = args.firstIndex(of: "-autoConfigureToken"),
           idx + 1 < args.count {
            KeychainStore.shared.isMockMode = false
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
                .tint(HermesTheme.accent)
                .preferredColorScheme(.dark)
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
