//
//  JarvisApp.swift
//  JARVIS
//

import SwiftUI

enum JarvisBrand {
    static let displayName = "JARVIS"
    static let assistantName = "JARVIS"
}

enum JarvisTheme {
    // JARVIS keeps its own green accent, but borrows the quiet, neutral
    // surfaces and low-chrome hierarchy of modern AI chat clients.
    static let background = Color(red: 0.125, green: 0.125, blue: 0.125)
    static let surface = Color(red: 0.180, green: 0.180, blue: 0.180)
    static let surfaceElevated = Color(red: 0.235, green: 0.235, blue: 0.235)
    static let userBubble = Color(red: 0.235, green: 0.235, blue: 0.235)
    static let border = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.075)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.42)
    static let accent = Color(red: 0.42, green: 0.82, blue: 0.60)
    static let accentSoft = Color(red: 0.25, green: 0.50, blue: 0.37)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let control: CGFloat = 14
        static let card: CGFloat = 18
        static let pill: CGFloat = 999
    }

    enum Typography {
        static let screenTitle = Font.system(size: 30, weight: .semibold)
        static let rowTitle = Font.system(size: 16, weight: .medium)
        static let body = Font.system(size: 16)
        static let metadata = Font.system(size: 13)
        static let eyebrow = Font.system(size: 12, weight: .semibold)
    }
}

@main
struct JarvisApp: App {
    @State private var appState = AppState()
    @State private var apiConfig = APIConfig()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        JarvisBackgroundTasks.register()
        #if DEBUG
        // Debug helpers for headless verification of the FirstRunView →
        // HomeView → ConversationView flow without manual typing.
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
                .tint(JarvisTheme.accent)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, new in
                    appState.scenePhase = new
                    if new == .background {
                        JarvisBackgroundTasks.scheduleRefresh()
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
                HomeView()
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
